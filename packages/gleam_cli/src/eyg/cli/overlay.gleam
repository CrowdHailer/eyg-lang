//// This module is the effectful implementation of the tool calls available to overlay.
//// The state passed to each tool call is a cache of state that is reusable between tool calls.
//// Currently this state is only used for keeping access tokens for authenticated calls to API's
//// The state is currently a bun specific implementation however as it is scoped to tool calls it could be moved to overlay
//// Moving the full application state to overlay core is a bad idea, because we want to track different state when streaming
//// vs using The Elm Architecture in a Lustre web app.
//// 
//// The code execution tool is defined sans io using an effect type defined in this project.
//// The other tools could use the same effect logic, this is probably a good idea once we start applying policies for which files can be read.

import eyg/cli/internal/config
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import midas/continuation.{type Continuation as K}
import ogre/origin
import overlay/agent
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/tools/run

// I don't need to implement streaming but if so that goes at the loam level
// the tools module in overlay web should be reusable
// policy is read as part of config, which can read files and effects. policy is pure

// Env should be readable on startup
pub fn execute(input, config: config.Config) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let state = execute.State(config.client.origin, cache.empty())
  use #(result, _state) <- system.then(execute.block(source, [], state))
  case result {
    Ok(#(Some(user_config), _)) ->
      case cast(user_config) {
        Ok(user_config) -> {
          let assert Ok(readme) =
            cast.field("readme", cast.as_string, user_config.context)
          use x <- system.then(
            outer_loop(
              user_config.llm,
              provider_context(config.client.origin, readme),
              cwd,
              state,
              user_config.policy,
              user_config.context,
              [],
            ),
          )
          echo x
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

pub type Config {
  Config(llm: provider.Llm, policy: execute.Value, context: execute.Value)
}

/// we can assume cast returns good values for policy and context because we should type check before hande
/// We need to extract the context type so it can be used as a module when evaluating
fn cast(value) {
  case
    cast.field("llm", cast_llm, value),
    cast.field("policy", Ok, value),
    cast.field("context", Ok, value)
  {
    Ok(provider), Ok(policy), Ok(context) -> {
      let llm = provider.Llm(provider:, model: "glm-5.3:cloud")
      Ok(Config(llm:, policy:, context:))
    }
    Error(reason), _, _ -> Error(reason)
    Ok(_), Error(reason), _ -> Error(reason)
    Ok(_), Ok(_), Error(reason) -> Error(reason)
  }
}

// cast is the wrong term, we need a decode API
fn cast_llm(value) {
  use tagged <- result.try(cast.as_tagged(value))
  case tagged {
    #("Ollama", inner) -> result.map(cast_ollama(inner), provider.Ollama)
    #(_, _) -> Error(break.NoMatch(value))
  }
}

fn cast_ollama(value) {
  use origin <- result.try(cast.field("origin", cast.as_string, value))
  use origin <- result.try(
    origin.from_string(origin)
    |> result.replace_error(break.IncorrectTerm("origin", value.String(origin))),
  )
  use api_key <- result.try(cast.field(
    "api_key",
    cast.as_option(_, cast.as_string),
    value,
  ))
  Ok(ollama.Config(origin:, api_key:))
}

// fn cast_policy(value) {
//   use read_file <- result.try(cast.field(
//     "read_file",
//     fn(raw) {
//       // if we've type checked we can assume the value is good
//       // let assert value.Closure(param:, body:, env:) = raw
//       // use #(_poly, type_, errors) <- system.then(check_from(
//       //   source,
//       //   cwd,
//       //   context,
//       // ))
//       Ok(raw)
//     },
//     value,
//   ))
//   echo read_file
//   Ok(Nil)
// }
// I call this chat because we're in a chat agent
import overlay/llm/chat

fn outer_loop(
  llm,
  provider_context,
  cwd,
  eyg_state,
  policy,
  user_context,
  history,
) {
  use read <- system.then(input(">>>", "send a message"))
  case read {
    Ok("") -> system.Done(Nil)
    Ok(text) -> {
      let history = [chat.UserMessage(text, []), ..history]
      use result <- system.then(inner_loop(
        llm,
        provider_context,
        cwd,
        eyg_state,
        policy,
        user_context,
        history,
      ))
      case result {
        Ok(history) ->
          outer_loop(
            llm,
            provider_context,
            cwd,
            eyg_state,
            policy,
            user_context,
            history,
          )
        Error(reason) -> {
          use Nil <- system.then(system.stdout(ansi.red(reason)))
          system.Done(Nil)
        }
      }
    }
    Error(Nil) -> system.Done(Nil)
  }
}

import gleam/io
import gleam/string
import gleam_community/ansi

pub fn input(
  prompt: String,
  placeholder: String,
) -> system.Effect(Result(String, Nil)) {
  let prompt = ansi.bold(ansi.yellow(prompt))
  io.print(prompt)
  io.print(" ")
  io.print(ansi.dim(placeholder))
  io.print("\r")
  io.print(prompt)
  io.print(" ")
  use return <- system.map(system.prompt(""))
  case return {
    Ok(line) -> Ok(string.trim_end(line))
    Error(reason) -> Error(reason)
  }
}

fn provider_context(origin: origin.Origin, readme: String) -> provider.Context {
  provider.Context(
    system_prompt: agent.system_prompt(origin, computer.effects(), readme),
    tools: [
      run.spec(),
    ],
  )
}

pub fn inner_loop(
  llm,
  provider_context,
  cwd,
  eyg_state,
  policy,
  context,
  history,
) {
  use completion <- system.then(provider.completion(
    llm,
    provider_context,
    list.reverse(history),
    fetch,
  )(system.Done))
  case completion {
    Ok(completion) -> {
      io.println(completion.content)
      let history = [chat.from_completion(completion), ..history]
      case completion.tool_calls {
        [] -> system.Done(Ok(history))
        calls -> {
          use #(history, eyg_state) <- system.then(
            system.fold(calls, #(history, eyg_state), fn(acc, call) {
              let #(history, eyg_state) = acc
              let tool.Call(id:, function:) = call
              use #(result, _) <- system.then(execute_call(
                function,
                cwd,
                eyg_state,
                policy,
                context,
              ))
              // let result = result.map(result, pair.first)
              let result = result_to_message(id, result)
              let history = [result, ..history]
              system.Done(#(history, eyg_state))
            }),
          )
          inner_loop(
            llm,
            provider_context,
            cwd,
            eyg_state,
            policy,
            context,
            history,
          )
        }
      }
    }
    Error(reason) -> system.Done(Error(reason))
  }
}

pub fn result_to_message(
  call_id: String,
  result: Result(tool.Return, String),
) -> chat.Message(a) {
  case result {
    Ok(tool.Return(text, images)) -> {
      chat.ToolResultMessage(tool_call_id: call_id, text:, images:)
    }
    Error(reason) ->
      chat.ToolResultMessage(tool_call_id: call_id, text: reason, images: [])
  }
}

fn fetch(
  request,
) -> K(system.Effect(_), Result(response.Response(BitArray), _)) {
  system.Fetch(request, _)
}

// ---------------------------- toools

import overlay/llm/tool

pub fn execute_call(
  call: tool.FunctionCall,
  cwd: String,
  eyg_state: execute.State,
  policy: execute.Value,
  context: execute.Value,
) -> system.Effect(#(Result(tool.Return, String), execute.State)) {
  let tool.FunctionCall(name, arguments) = call
  case agent.cast_tool_call(name, arguments) {
    Ok(call) -> {
      io.println(ansi.bg_bright_green(log_line(call)))
      case call {
        agent.Run(code) -> {
          use #(result, eyg_state, output) <- system.then(run_do(
            code,
            cwd,
            eyg_state,
            policy,
            context,
          ))
          let result = case result {
            // current state is not used by the CLI implementation, this will need to change.
            Ok(#(Some(value), _)) -> {
              Ok(tool.Return(report(output, simple_debug.inspect(value)), []))
            }
            Ok(#(None, _)) -> Ok(tool.Return(report(output, ""), []))
            Error(reason) -> {
              Error(report(output, reason))
            }
          }
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
    agent.Run(_code) -> "Executing EYG code."
  }
}

/// Output is collected newest-first, scoped to a single tool call.
fn report(output: List(String), result: String) -> String {
  case list.reverse(output) {
    [] -> result
    printed -> "Output:\n" <> string.concat(printed) <> "\nResult:\n" <> result
  }
}

// There's a problem that the final execute is tied to runtime
// ---------------------- run

pub fn run_do(
  code,
  cwd,
  eyg_state,
  policy: execute.Value,
  context: execute.Value,
) -> system.Effect(#(Result(_, String), execute.State, List(String))) {
  let input = source.Stdin

  case source.parse_input(code, input) {
    Ok(source) -> {
      let scope = [#("context", context)]
      let assert Ok(policy) = cast_policy(policy)
      use #(result, state, output) <- system.map(
        loop(block.execute(source, scope), eyg_state, policy, []),
      )
      let result = case result {
        Ok(value) -> Ok(value)
        Error(#(reason, location, _env, k)) ->
          Error(execute.render_error(reason, location, k, cwd))
      }
      #(result, state, output)
    }
    Error(reason) -> system.Done(#(Error(reason), eyg_state, []))
  }
}

// allow/mock
// forward/mock
// allow/deny
// Pass/mock
fn cast_policy(value) {
  use append_file <- result.try(cast.field("append_file", Ok, value))
  use create_key <- result.try(cast.field("create_key", Ok, value))
  use cwd <- result.try(cast.field("cwd", Ok, value))
  // use decode_json <- result.try(cast.field("decode_json", Ok, value))
  use delete_file <- result.try(cast.field("delete_file", Ok, value))
  use env <- result.try(cast.field("env", Ok, value))
  // use exit <- result.try(cast.field("exit", Ok, value))
  // use eyg_parse <- result.try(cast.field("eyg_parse", Ok, value))
  use fetch <- result.try(cast.field("fetch", Ok, value))
  // use flip <- result.try(cast.field("flip", Ok, value))
  // use hash <- result.try(cast.field("hash", Ok, value))
  use make_directory <- result.try(cast.field("make_directory", Ok, value))
  use now <- result.try(cast.field("now", Ok, value))
  use random <- result.try(cast.field("random", Ok, value))
  use read_directory <- result.try(cast.field("read_directory", Ok, value))
  use read_file <- result.try(cast.field("read_file", Ok, value))
  use sign <- result.try(cast.field("sign", Ok, value))
  use sleep <- result.try(cast.field("sleep", Ok, value))
  use standard_error <- result.try(cast.field("standard_error", Ok, value))
  use standard_in <- result.try(cast.field("standard_in", Ok, value))
  use standard_out <- result.try(cast.field("standard_out", Ok, value))
  use write_file <- result.try(cast.field("write_file", Ok, value))
  [
    #("AppendFile", append_file),
    #("CreateKey", create_key),
    #("CWD", cwd),
    // #("Decode_json", decode_json),
    #("DeleteFile", delete_file),
    #("Env", env),
    // #("Exit", exit),
    // #("Eyg_parse", eyg_parse),
    #("Fetch", fetch),
    // #("Flip", flip),
    // #("Hash", hash),
    #("MakeDirectory", make_directory),
    #("Now", now),
    #("Random", random),
    #("ReadDirectory", read_directory),
    #("ReadFile", read_file),
    #("Sign", sign),
    #("Sleep", sleep),
    #("StandardError", standard_error),
    #("StandardIn", standard_in),
    #("StandardOut", standard_out),
    #("WriteFile", write_file),
  ]
  |> Ok
}

fn apply_policy(label, value, meta, policy, state) {
  case list.key_find(policy, label) {
    Ok(run) -> execute.pure_loop(expression.call(run, [#(value, meta)]), state)
    Error(Nil) -> system.Done(#(Ok(value.Tagged("Pass", value)), state))
  }
}

// This is a replacement for execute.loop because of the police
pub fn loop(
  return: Result(_, execute.Debug),
  state: execute.State,
  policy: List(#(String, execute.Value)),
  output: List(String),
) -> system.Effect(#(Result(_, execute.Debug), execute.State, List(String))) {
  case return {
    Ok(return) -> system.Done(#(Ok(return), state, output))
    Error(#(reason, meta, env, k)) ->
      case reason {
        break.UnhandledEffect(label, lift) -> {
          // let assert Ok(policy) = cast_policy(policy)
          use #(result, state) <- system.then(apply_policy(
            label,
            lift,
            meta,
            policy,
            state,
          ))
          case result {
            Ok(value.Tagged(label: "Pass", value: modified)) ->
              case computer.cast(label, modified) {
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
            Ok(value.Tagged(label: "Mock", value: returned)) ->
              loop(block.resume(returned, env, k), state, policy, output)
            _ -> system.Done(#(Error(#(reason, meta, env, k)), state, output))
          }
        }
        break.UndefinedReference(reference) -> {
          use #(result, state) <- system.then(execute.lookup(
            reference,
            meta.origin,
            state,
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
