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
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
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
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/pair
import gleam/result
import gleam/string
import gleam_community/ansi
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import midas/continuation.{type Continuation as K}
import overlay/agent
import overlay/config as overlay_config
import overlay/export
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
pub type Session(eff) {
  Session(
    llm: provider.Llm,
    provider_context: provider.Context,
    cwd: String,
    policy: policy.Policy(eff, source.Location),
    context: cache.Module(source.Location),
    styled: Bool,
  )
}

// Move with_variable and with_scope to analysis
// check should be on run/script/shell etc and test the right things
// --no-check can be an option
// pass in a policy should be possible in other commands such as REPL etc
// Safety in the language i.e. sandbox 
// policy can have a debug effect during running it so we can see what's happening.
// type check some new code and then eval returns Effect(value, resume)
// This is the API choices such as use of types around eval can setup what's passed in.
// TODO relative imports and file lookup
pub fn execute(
  input: source.Input,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  let state = execute.State(config.client.origin, cache.empty())
  use #(result, state) <- system.then(setup(
    input,
    config,
    computer.effects(),
    rule_mapping,
    state,
  ))
  use session <- system.try(result)
  use Nil <- system.then(outer_loop(session, state, []))
  Ok(0) |> system.Done
}

fn try(result, state, then) {
  case result {
    Ok(value) -> then(value)
    Error(reason) -> system.Done(#(Error(reason), state))
  }
}

/// Setup the chat session.
/// The `Session` contains all information that is constant over the conversation
/// 
/// The `config` arg could be broken down as not that many parts are needed
/// The harness and rule_mappings are passed in to make building other CLI tools easier
pub fn setup(
  input: source.Input,
  config: config.Config,
  harness: interface.Harness(harness_computer.Effect, source.Location),
  rule_mapping: List(#(String, policy.Rule)),
  state: execute.State,
) -> system.Effect(
  #(Result(Session(harness_computer.Effect), String), execute.State),
) {
  use cwd <- system.then(system.cwd())
  use cwd <- try(cwd, state)
  use input <- try(source.normalize_input(cwd, input), state)
  use code <- system.then(source.read_input(input))
  use code <- try(code, state)
  use source <- try(source.parse_input(code, input), state)

  // The harness bound with the rules
  let agent_harness = policy.match_rules(harness, rule_mapping)

  let context =
    infer.pure()
    // The policy is evaluated outside the policy and can access any effect
    |> infer.with_effects(interface.types(harness))
  let #(expected, context_type, bindings) =
    overlay_config.type_(agent_harness, context.level, context.bindings)
  let context =
    infer.Context(..context, bindings:)
    |> infer.with_expected_type(expected)

  // TODO this analysis should return updated state
  use #(_type, _, errors, analysis) <- system.then(check.check_from(
    source,
    cwd,
    context,
    state,
    check.allway_pass_gate,
  ))
  use Nil <- try(
    case errors {
      [] -> Ok(Nil)
      _ -> Error(list.map(errors, check.render_error) |> string.join("\n"))
    },
    state,
  )

  let context_poly = {
    let mono = binding.resolve(context_type, analysis.bindings)
    binding.gen(mono, 0, analysis.bindings)
  }
  use #(result, state) <- system.then(execute.block(source, [], state))
  case result {
    Ok(#(Some(user_config), _)) ->
      case overlay_config.cast(user_config, agent_harness) {
        Ok(user_config) -> {
          let session =
            Session(
              llm: user_config.llm,
              provider_context: provider.Context(
                system_prompt: agent.system_prompt(
                  config.client.origin,
                  // use the agent harness because the prompt should talk about effects that can't be used
                  list.map(agent_harness, pair.first),
                  user_config.readme,
                  True,
                ),
                tools: agent.tools(),
              ),
              cwd:,
              policy: user_config.policy,
              context: cache.Module(
                value: user_config.context,
                type_: context_poly,
              ),
              styled: config.styled,
            )

          system.Done(#(Ok(session), state))
        }
        Error(reason) ->
          #(
            Error(execute.render_error(reason, source.1, state.Empty, cwd)),
            state,
          )
          |> system.Done
      }
    Ok(#(None, _)) ->
      #(
        Error(execute.render_error(break.Vacant, source.1, state.Empty, cwd)),
        state,
      )
      |> system.Done
    Error(#(reason, location, _, k)) ->
      #(Error(execute.render_error(reason, location, k, cwd)), state)
      |> system.Done
  }
}

/// A chat based outer loop, this is the layer that a ralph loop would replace
fn outer_loop(
  session: Session(harness_computer.Effect),
  eyg_state: execute.State,
  history: List(chat.Message(tool.Call)),
) -> system.Effect(Nil) {
  use read <- system.then(input(session.styled, ">>>", "send a message"))
  case read {
    Ok("") -> system.Done(Nil)
    Ok("/export" <> path) -> {
      use Nil <- system.then(export(session, history, string.trim(path)))
      outer_loop(session, eyg_state, history)
    }
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
            terminal.style(session.styled, ansi.red, reason) <> "\n",
          ))
          system.Done(history)
        }
      })
      outer_loop(session, eyg_state, history)
    }
    Error(Nil) -> system.Done(Nil)
  }
}

fn input(
  noninteractive: Bool,
  prompt: String,
  placeholder: String,
) -> system.Effect(Result(String, Nil)) {
  let prompt = case noninteractive {
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
/// This is a sequential inner loop
pub fn inner_loop(
  session: Session(harness_computer.Effect),
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

fn result_to_message(
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

fn execute_call(
  session: Session(harness_computer.Effect),
  call: tool.FunctionCall,
  eyg_state: execute.State,
) -> system.Effect(#(Result(tool.Return, String), execute.State)) {
  let tool.FunctionCall(name, arguments) = call
  case agent.cast_tool_call(name, arguments) {
    Ok(call) -> {
      use Nil <- system.then(system.stdout(log_line(session.styled, call)))
      case call {
        agent.Run(code) -> {
          use #(result, eyg_state, output) <- system.then(check_and_execute(
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
          use Nil <- system.then(
            system.stdout(log_result(session.styled, result)),
          )
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

fn log_line(noninteractive, call) {
  case call {
    agent.Run(code) ->
      terminal.style(
        noninteractive,
        ansi.bg_bright_green,
        "Executing EYG code.",
      )
      <> "\n"
      <> terminal.style(noninteractive, ansi.dim, code)
  }
}

/// Summarise a tool call result so the user can see what the agent saw.
fn log_result(noninteractive, result: Result(tool.Return, String)) -> String {
  case result {
    Ok(tool.Return(text:, ..)) ->
      terminal.style(noninteractive, ansi.green, "ok ")
      <> terminal.style(noninteractive, ansi.dim, truncate(text))
    Error(reason) ->
      terminal.style(noninteractive, ansi.red, "error ")
      <> terminal.style(noninteractive, ansi.dim, truncate(reason))
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

/// If extracted this would be the implementation of a tool called run.
/// In a module run.gleam this would be the execute function
/// A better name might be check_and_execute
pub fn check_and_execute(
  session: Session(harness_computer.Effect),
  code: String,
  eyg_state: execute.State,
) -> system.Effect(#(Result(_, String), execute.State, List(String))) {
  let input = source.Stdin

  case source.parse_input(code, input) {
    Ok(source) -> {
      use errors <- system.then(type_check(session, source, eyg_state))
      case errors {
        [] -> {
          let scope = [#("context", session.context.value)]

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
        _errors -> system.Done(#(Error("type error"), eyg_state, []))
      }
    }
    Error(reason) -> system.Done(#(Error(reason), eyg_state, []))
  }
}

fn type_check(session: Session(_), source, eyg_state) {
  let base =
    infer.pure()
    |> infer.with_effects(interface.types(
      dict.values(session.policy) |> list.map(fn(i) { i.interface }),
    ))
    // Aborting ends the program, it is not an effect of the platform so is never gated.
    |> infer.with_effect("Abort", t.String, t.Never)
  // this is an infer context
  let context =
    infer.Context(..base, env: [#("context", session.context.type_), ..base.env])
  use #(_, _, errors, _) <- system.map(check.check_from(
    source,
    session.cwd,
    context,
    eyg_state,
    import_gate(session.policy, source.1),
    // Don't use check_from instead expose the lookup function from check so reference lookup is reusable.
  ))
  errors
}

/// The ReadFile request a relative import of `path` is decided by.
fn import_request(path) {
  value.Record(
    dict.from_list([
      #("path", value.String(path)),
      #("offset", value.Integer(0)),
      #("limit", value.Integer(100_000_000)),
    ]),
  )
}

/// Decide the agent's relative imports when type checking, as they are decided when it runs.
/// Policies are pure so asking the ReadFile gate performs no effects.
fn import_gate(
  policy: policy.Policy(harness_computer.Effect, source.Location),
  meta: source.Location,
) {
  fn(path, state) {
    use #(decided, state) <- system.map(decide(
      policy,
      "ReadFile",
      import_request(path),
      meta,
      state,
    ))
    let path = case decided {
      policy.Perform(_, modified) ->
        cast.field("path", cast.as_string, modified)
        |> result.replace_error(Nil)
      policy.Resume(_) | policy.Failed(_) | policy.Unavailable -> Error(Nil)
    }
    #(path, state)
  }
}

/// This is a replacement for execute.loop because of the policy
/// In the future a unrestrained harness can have a rule of unrestrained for all interfaces
fn loop(
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

/// Resolve filesystem paths before a policy sees them. Other request fields
/// stay intact, and the interface decoder still validates malformed requests.
/// 
/// This is an unfortunet amount of knowledge about the effects.
/// Maybe all filesystem effects should be absolute
fn resolve_policy_input(label, lift, origin) {
  case label, lift {
    "ReadFile", value.Record(fields)
    | "WriteFile", value.Record(fields)
    | "AppendFile", value.Record(fields)
    ->
      case dict.get(fields, "path") {
        Ok(value.String(path)) -> {
          use resolved <- system.map(source.resolve_filepath(origin, path))
          use path <- result.map(resolved)
          value.Record(dict.insert(fields, "path", value.String(path)))
        }
        _ -> system.Done(Ok(lift))
      }
    "DeleteFile", value.String(path)
    | "MakeDirectory", value.String(path)
    | "ReadDirectory", value.String(path)
    -> {
      use resolved <- system.map(source.resolve_filepath(origin, path))
      result.map(resolved, value.String)
    }
    _, _ -> system.Done(Ok(lift))
  }
}

/// Call the gate with absolute filesystem paths. Policy redirects must also
/// use absolute paths. Unchecked effects are always performed.
/// This could take a call as a continuation in which case the need for state would drop out
/// To extract to policy would require the continuation change
fn decide(
  policy: policy.Policy(harness_computer.Effect, source.Location),
  label: String,
  lift: execute.Value,
  meta: source.Location,
  state: execute.State,
) -> system.Effect(
  #(policy.Action(source.Location, harness_computer.Effect), execute.State),
) {
  use resolved <- system.then(resolve_policy_input(label, lift, meta.origin))
  case resolved {
    Ok(lift) -> decide_resolved(policy, label, lift, meta, state)
    // Path resolution failures are ordinary filesystem effect errors.
    Error(reason) ->
      system.Done(#(policy.Resume(value.error(value.String(reason))), state))
  }
}

fn decide_resolved(policy, label, lift, meta, state) {
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

// Resolve imports before asking the ReadFile gate, matching type checking.
// This is lookup_reference_value there is a separate lookup_reference_type
// is it worth loam/execute.lookup_relative handling a policy, maybe if eval and spawn is included.
fn lookup_reference(reference, meta: source.Location, state, policy) {
  case reference {
    ir.Relative(path) -> {
      use resolved <- system.then(source.resolve_filepath(meta.origin, path))
      use path <- try(
        result.replace_error(resolved, break.UndefinedReference(reference)),
        state,
      )
      let request = import_request(path)
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
            Ok(path) ->
              execute.lookup_relative(
                path,
                meta.origin,
                state,
                fn(reference, meta, state) {
                  // lookup reference in overlay accepts the policy
                  lookup_reference(reference, meta, state, policy)
                },
              )
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

// Only deterministic computations over supplied values bypass policy.
// Randomness and process termination are observable effects, even without file IO.
pub const rule_mapping = [
  #("AppendFile", policy.PolicyField("append_file")),
  #("CreateKey", policy.PolicyField("create_key")),
  #("CWD", policy.PolicyField("cwd")),
  #("DecodeJSON", policy.Unchecked),
  #("DeleteFile", policy.PolicyField("delete_file")),
  #("Env", policy.PolicyField("env")),
  #("Exit", policy.PolicyField("exit")),
  #("EYGParse", policy.Unchecked),
  #("Fetch", policy.PolicyField("fetch")),
  #("Flip", policy.PolicyField("flip")),
  #("Hash", policy.Unchecked),
  #("MakeDirectory", policy.PolicyField("make_directory")),
  #("Now", policy.PolicyField("now")),
  #("Random", policy.PolicyField("random")),
  #("ReadDirectory", policy.PolicyField("read_directory")),
  #("ReadFile", policy.PolicyField("read_file")),
  #("Sign", policy.Unchecked),
  #("Sleep", policy.PolicyField("sleep")),
  #("StandardError", policy.PolicyField("standard_error")),
  #("StandardIn", policy.PolicyField("standard_in")),
  #("StandardOut", policy.PolicyField("standard_out")),
  #("WriteFile", policy.PolicyField("write_file")),
]

/// Write the chat in the opencode session export format.
fn export(
  session: Session(harness_computer.Effect),
  history: List(chat.Message(tool.Call)),
  path: String,
) -> system.Effect(Nil) {
  use time <- system.then(system.now())
  let path = case path {
    "" -> "overlay-session-" <> int.to_string(time) <> ".json"
    path -> path
  }
  let exported =
    export.encode(
      export.Session(
        id: "ses_" <> int.to_string(time),
        directory: session.cwd,
        provider_id: provider.id(session.llm.provider),
        model_id: session.llm.model,
        time:,
      ),
      list.reverse(history),
    )
    |> json.to_string
  use resolved <- system.then(source.resolve_filepath(source.Pipe, path))
  let path = result.unwrap(resolved, path)
  use result <- system.then(system.write_file(path, exported))
  system.stdout(case result {
    Ok(Nil) -> "exported session to " <> path
    Error(reason) ->
      terminal.style(
        session.styled,
        ansi.red,
        "failed to export session: " <> string.inspect(reason),
      )
  })
}
