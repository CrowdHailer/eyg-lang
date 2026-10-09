//// This module is the effectful implementation of the tool calls available to overlay.
//// The state passed to each tool call is a cache of state that is reusable between tool calls.
//// Currently this state is only used for keeping access tokens for authenticated calls to API's
//// The state is currently a bun specific implementation however as it is scoped to tool calls it could be moved to overlay
//// Moving the full application state to overlay core is a bad idea, because we want to track different state when streaming
//// vs using The Elm Architecture in a Lustre web app.
//// 
//// The code execution tool is defined sans io using an effect type defined in this project.
//// The other tools could use the same effect logic, this is probably a good idea once we start applying policies for which files can be read.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/cli/check
import eyg/cli/internal/config
import eyg/cli/internal/terminal
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value
import eyg/ir/tree as ir
import gleam/dict
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam_community/ansi
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import midas/continuation.{type Continuation as K}
import overlay/agent
import overlay/config as overlay_config
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool
import overlay/policy
import overlay/tools/run
import touch_grass/harness/computer as harness_computer
import touch_grass/interface

// I don't need to implement streaming but if so that goes at the loam level
// the tools module in overlay web should be reusable
// policy is read as part of config, which can read files and effects. policy is pure

// Env should be readable on startup
/// Everything about a session that is fixed when it starts.
pub type Session {
  Session(
    llm: provider.Llm,
    provider_context: provider.Context,
    cwd: String,
    policy: policy.Policy(harness_computer.Effect, source.Location),
    context: execute.Value,
  )
}

pub fn execute(input, config: config.Config) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let state = execute.State(config.client.origin, cache.empty())
  let rules = policy_rules()
  let context =
    infer.pure()
    |> infer.with_effects(interface.types(computer.effects()))
  let #(expected, bindings) =
    overlay_config.type_(rules, context.level, context.bindings)
  let context =
    infer.Context(..context, bindings:)
    |> infer.with_expected_type(expected)
  use #(_, _, errors) <- system.then(check.check_from(
    source,
    cwd,
    context,
    state,
  ))
  use Nil <- system.try(case errors {
    [] -> Ok(Nil)
    _ -> Error(list.map(errors, check.render_error) |> string.join("\n"))
  })
  use #(result, state) <- system.then(execute.block(source, [], state))
  case result {
    Ok(#(Some(user_config), _)) ->
      case overlay_config.cast(user_config, rules) {
        Ok(user_config) -> {
          let session =
            Session(
              llm: user_config.llm,
              provider_context: provider.Context(
                system_prompt: agent.system_prompt(
                  config.client.origin,
                  computer.effects(),
                  user_config.readme,
                ),
                tools: agent.tools(),
              ),
              cwd:,
              policy: user_config.policy,
              context: user_config.context,
            )
          use Nil <- system.then(outer_loop(session, state, []))
          Ok(0) |> system.Done
        }
        Error(reason) ->
          Error(execute.render_error(reason, source.1, state.Empty, cwd))
          |> system.Done
      }
    Ok(#(None, _)) ->
      Error(execute.render_error(break.Vacant, source.1, state.Empty, cwd))
      |> system.Done
    Error(#(reason, location, _, k)) ->
      Error(execute.render_error(reason, location, k, cwd)) |> system.Done
  }
}

fn outer_loop(
  session: Session,
  eyg_state: execute.State,
  history: List(chat.Message(tool.Call)),
) -> system.Effect(Nil) {
  use read <- system.then(input(">>>", "send a message"))
  case read {
    Ok("") -> system.Done(Nil)
    Ok(text) -> {
      use #(result, eyg_state) <- system.then(
        inner_loop(session, eyg_state, [chat.UserMessage(text, []), ..history]),
      )
      // A failed completion is reported and the session continues from the
      // history before the failed message, so the user can try again.
      use history <- system.then(case result {
        Ok(history) -> system.Done(history)
        Error(reason) -> {
          // This output should be error and potentially show to the agent.
          use Nil <- system.then(system.stdout(
            terminal.style(ansi.red, reason) <> "\n",
          ))
          system.Done(history)
        }
      })
      outer_loop(session, eyg_state, history)
    }
    Error(Nil) -> system.Done(Nil)
  }
}

pub fn input(
  prompt: String,
  placeholder: String,
) -> system.Effect(Result(String, Nil)) {
  let prompt = case terminal.noninteractive() {
    // The placeholder is overwritten as the user types.
    True -> {
      let prompt = ansi.bold(ansi.yellow(prompt))
      prompt <> " " <> ansi.dim(placeholder) <> "\r" <> prompt <> " "
    }
    False -> prompt <> " "
  }
  use return <- system.map(system.prompt(prompt))
  case return {
    Ok(line) -> Ok(string.trim_end(line))
    Error(reason) -> Error(reason)
  }
}

/// Complete and run tool calls until the agent replies without calling a tool.
pub fn inner_loop(
  session: Session,
  eyg_state: execute.State,
  history: List(chat.Message(tool.Call)),
) -> system.Effect(
  #(Result(List(chat.Message(tool.Call)), String), execute.State),
) {
  use completion <- system.then(provider.completion(
    session.llm,
    session.provider_context,
    list.reverse(history),
    fetch,
  )(system.Done))
  case completion {
    Ok(completion) -> {
      use Nil <- system.then(system.stdout(completion.content))
      let history = [chat.from_completion(completion), ..history]
      case completion.tool_calls {
        [] -> system.Done(#(Ok(history), eyg_state))
        calls -> {
          use #(history, eyg_state) <- system.then(
            system.fold(calls, #(history, eyg_state), fn(acc, call) {
              let #(history, eyg_state) = acc
              let tool.Call(id:, function:) = call
              use #(result, eyg_state) <- system.then(execute_call(
                session,
                function,
                eyg_state,
              ))

              let history = [result_to_message(id, result), ..history]
              system.Done(#(history, eyg_state))
            }),
          )
          inner_loop(session, eyg_state, history)
        }
      }
    }
    Error(reason) -> system.Done(#(Error(reason), eyg_state))
  }
}

pub fn result_to_message(
  call_id: String,
  result: Result(tool.Return, String),
) -> chat.Message(a) {
  case result {
    Ok(tool.Return(text, images)) -> {
      chat.ToolResultMessage(
        tool_call_id: call_id,
        text: agent.tool_result_text(text),
        images:,
      )
    }
    Error(reason) ->
      chat.ToolResultMessage(
        tool_call_id: call_id,
        text: agent.tool_result_text(reason),
        images: [],
      )
  }
}

fn fetch(
  request,
) -> K(system.Effect(_), Result(response.Response(BitArray), _)) {
  system.Fetch(request, _)
}

// ---------------------------- toools

pub fn execute_call(
  session: Session,
  call: tool.FunctionCall,
  eyg_state: execute.State,
) -> system.Effect(#(Result(tool.Return, String), execute.State)) {
  let tool.FunctionCall(name, arguments) = call
  case agent.cast_tool_call(name, arguments) {
    Ok(call) -> {
      use Nil <- system.then(system.stdout(log_line(call)))
      case call {
        agent.Run(code) -> {
          use #(result, eyg_state, output) <- system.then(run_do(
            session,
            code,
            eyg_state,
          ))
          let result = case result {
            // current state is not used by the CLI implementation, this will need to change.
            Ok(#(Some(value), _)) -> {
              Ok(
                tool.Return(run.report(output, agent.inspect_result(value)), []),
              )
            }
            Ok(#(None, _)) -> Ok(tool.Return(run.report(output, ""), []))
            Error(reason) -> Error(run.report(output, reason))
          }
          use Nil <- system.then(system.stdout(log_result(result)))
          system.Done(#(result, eyg_state))
        }
      }
    }
    Error(reason) ->
      system.Done(#(
        Error(agent.describe_failure(reason, name, arguments)),
        eyg_state,
      ))
  }
}

pub fn log_line(call) {
  case call {
    agent.Run(code) ->
      terminal.style(ansi.bg_bright_green, "Executing EYG code.")
      <> "\n"
      <> terminal.style(ansi.dim, code)
  }
}

/// Summarise a tool call result so the user can see what the agent saw.
fn log_result(result: Result(tool.Return, String)) -> String {
  case result {
    Ok(tool.Return(text:, ..)) ->
      terminal.style(ansi.green, "ok ")
      <> terminal.style(ansi.dim, truncate(text))
    Error(reason) ->
      terminal.style(ansi.red, "error ")
      <> terminal.style(ansi.dim, truncate(reason))
  }
}

fn truncate(text) {
  case string.length(text) > 500 {
    True -> string.slice(text, 0, 500) <> "..."
    False -> text
  }
}

// There's a problem that the final execute is tied to runtime
// ---------------------- run

pub fn run_do(
  session: Session,
  code: String,
  eyg_state: execute.State,
) -> system.Effect(#(Result(_, String), execute.State, List(String))) {
  let input = source.Stdin

  case source.parse_input(code, input) {
    Ok(source) -> {
      let scope = [#("context", session.context)]

      use #(result, state, output) <- system.map(
        loop(block.execute(source, scope), eyg_state, session.policy, []),
      )
      let result = case result {
        Ok(value) -> Ok(value)
        Error(#(reason, location, _env, k)) ->
          Error(execute.render_error(reason, location, k, session.cwd))
      }
      #(result, state, output)
    }
    Error(reason) -> system.Done(#(Error(reason), eyg_state, []))
  }
}

// This is a replacement for execute.loop because of the police
pub fn loop(
  return: Result(_, execute.Debug),
  state: execute.State,
  policy: policy.Policy(_, _),
  output: List(String),
) -> system.Effect(#(Result(_, execute.Debug), execute.State, List(String))) {
  case return {
    Ok(return) -> system.Done(#(Ok(return), state, output))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UnhandledEffect(label, lift) -> {
          use #(decided, state) <- system.then(decide(
            policy,
            label,
            lift,
            meta,
            state,
          ))
          case decided {
            // This could return just the decoded value but that would require keeping meta data for the full debug state.
            policy.Perform(interface, modified) ->
              case interface.decode(modified) {
                Ok(effect) -> {
                  let effect = computer.extrinsic(effect, meta.origin)
                  // Capture the actual write after policy transformation while
                  // still forwarding it to the terminal.
                  let output = case effect {
                    system.WriteStdout(text, _) -> [text, ..output]
                    system.WriteStderr(text, _) -> [text, ..output]
                    _ -> output
                  }
                  use value <- system.then(effect)
                  loop(block.resume(value, env, k), state, policy, output)
                }
                Error(reason) ->
                  system.Done(#(Error(#(reason, meta, env, k)), state, output))
              }
            policy.Resume(returned) ->
              loop(block.resume(returned, env, k), state, policy, output)
            policy.Failed(debug) -> system.Done(#(Error(debug), state, output))
            policy.Unavailable ->
              system.Done(#(Error(#(reason, meta, env, k)), state, output))
          }
        }
        break.UndefinedReference(reference) -> {
          use #(result, state) <- system.then(lookup_reference(
            reference,
            meta,
            state,
            policy,
          ))
          case result {
            Ok(value) ->
              loop(block.resume(value, env, k), state, policy, output)
            Error(reason) ->
              system.Done(#(Error(#(reason, meta, env, k)), state, output))
          }
        }

        _ -> system.Done(#(Error(#(reason, meta, env, k)), state, output))
      }
  }
}

/// Call the gate for an effect, unchecked effects are always performed.
/// This could take a call as a continuation in which case the need for state would drop out
/// To extract to policy would require the continuation change
fn decide(
  policy: policy.Policy(harness_computer.Effect, source.Location),
  label: String,
  lift: execute.Value,
  meta: source.Location,
  state: execute.State,
) -> system.Effect(#(policy.Action(_, _), execute.State)) {
  case dict.get(policy, label) {
    Ok(policy.Interface(interface, policy.Gated(gate))) -> {
      let return = expression.call(gate, [#(lift, meta)])
      use #(result, state) <- system.map(execute.pure_loop(return, state))
      let decided = case result {
        Ok(value) ->
          case policy.decision_from_value(value) {
            Ok(policy.Pass(modified)) -> policy.Perform(interface, modified)
            Ok(policy.Mock(returned)) -> policy.Resume(returned)
            Error(Nil) ->
              policy.Failed(#(
                break.IncorrectTerm(expected: "Pass/Mock", got: value),
                meta,
                builtin.default([]),
                state.Empty,
              ))
          }
        Error(debug) -> policy.Failed(debug)
      }
      #(decided, state)
    }
    Ok(policy.Interface(interface, policy.Unrestricted)) ->
      system.Done(#(policy.Perform(interface, lift), state))
    Error(Nil) -> system.Done(#(policy.Unavailable, state))
  }
}

// Relative imports read files, so ask the ReadFile gate before resolving them.
fn lookup_reference(reference, meta, state, policy) {
  case reference {
    ir.Relative(path) -> {
      let request =
        value.Record(
          dict.from_list([
            #("path", value.String(path)),
            #("offset", value.Integer(0)),
            #("limit", value.Integer(100_000_000)),
          ]),
        )
      use #(decided, state) <- system.then(decide(
        policy,
        "ReadFile",
        request,
        meta,
        state,
      ))
      case decided {
        policy.Perform(_, modified) ->
          case cast.field("path", cast.as_string, modified) {
            Ok(path) -> execute.lookup(ir.Relative(path), meta.origin, state)
            Error(reason) -> system.Done(#(Error(reason), state))
          }
        policy.Resume(value.Tagged("Error", reason)) ->
          system.Done(#(
            Error(break.UnhandledEffect(
              "Abort",
              value.String(
                "import of "
                <> path
                <> " denied by policy: "
                <> simple_debug.inspect(reason),
              ),
            )),
            state,
          ))
        policy.Resume(returned) ->
          system.Done(#(
            Error(break.IncorrectTerm(
              "Pass(request) or Mock(Error(reason)) for an import",
              returned,
            )),
            state,
          ))
        policy.Failed(#(reason, _, _, _)) ->
          system.Done(#(Error(reason), state))
        policy.Unavailable ->
          system.Done(#(
            Error(break.UnhandledEffect("ReadFile", request)),
            state,
          ))
      }
    }
    _ -> execute.lookup(reference, meta.origin, state)
  }
}

pub fn policy_rules() {
  policy.match_rules(computer.effects(), [
    #("AppendFile", policy.PolicyField("append_file")),
    #("CreateKey", policy.PolicyField("create_key")),
    #("CWD", policy.PolicyField("cwd")),
    #("DecodeJSON", policy.Unchecked),
    #("DeleteFile", policy.PolicyField("delete_file")),
    #("Env", policy.PolicyField("env")),
    #("Exit", policy.Unchecked),
    #("EYGParse", policy.Unchecked),
    #("Fetch", policy.PolicyField("fetch")),
    #("Flip", policy.Unchecked),
    #("Hash", policy.Unchecked),
    #("MakeDirectory", policy.PolicyField("make_directory")),
    #("Now", policy.PolicyField("now")),
    #("Random", policy.Unchecked),
    #("ReadDirectory", policy.PolicyField("read_directory")),
    #("ReadFile", policy.PolicyField("read_file")),
    #("Sign", policy.PolicyField("sign")),
    #("Sleep", policy.PolicyField("sleep")),
    #("StandardError", policy.PolicyField("standard_error")),
    #("StandardIn", policy.PolicyField("standard_in")),
    #("StandardOut", policy.PolicyField("standard_out")),
    #("WriteFile", policy.PolicyField("write_file")),
  ])
}
