//// The cloud adapter for Overlay's sequential completion/tool loop.
////
//// `reply` is the loop as code that waits for each completion, so a session can record and replay it.
//// `inner_loop` performs each completion as it is reached, for channels that keep their history in memory.

import cloud/beam/execute
import cloud/system
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/string
import midas/continuation
import midas/effect
import multiformats/cid/v1
import ogre/origin
import overlay/agent
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool
import overlay/policy
import overlay/tools/run
import touch_grass/harness/computer

/// Everything about an agent session that is fixed when it starts.
pub type Session {
  Session(
    llm: provider.Llm,
    provider_context: provider.Context,
    fetch: fn(request.Request(BitArray)) ->
      Result(response.Response(BitArray), effect.FetchError),
  )
}

pub fn setup(hub: origin.Origin, llm: provider.Llm) -> Session {
  let provider_context =
    context(
      hub,
      "context is an empty record. The working directory is /. Files belong to this conversation and are shared with direct code execution. Relative imports load modules from these files. Env reads configured workspace secrets and returns Some(value) or None({}) when missing. Respond using the chat platform's Markdown formatting.",
    )
  Session(llm:, provider_context:, fetch: fn(request) {
    system.fetch(request)(fn(x) { x })
  })
}

fn context(hub, readme) {
  let effects =
    computer.effects()
    |> policy.match_rules(execute.rules)
    |> list.map(fn(rule) { rule.0 })
  provider.Context(
    system_prompt: agent.system_prompt(hub, effects, readme),
    tools: agent.tools(),
  )
}

/// The context of a chat in a box.
pub fn box_context(hub: origin.Origin) -> provider.Context {
  context(
    hub,
    "context is an empty record. The working directory is / of a box, a file system that other sessions in the box also change. Changes to .eyg files are only kept if every module in the box type checks. Relative imports load modules from these files.",
  )
}

/// Reply to a message, running the code of every tool call until the llm answers without one.
/// `history` is the chat before the message, oldest first.
/// The changes made by a tool call are kept even if it fails, the llm is told it failed.
pub fn reply(
  llm: provider.Llm,
  context: provider.Context,
  history: chat.History,
  message: String,
  policy: execute.Policy,
  state: execute.State,
  root: v1.Cid,
) -> execute.Run(String) {
  ask(
    llm,
    context,
    history,
    [chat.UserMessage(message, [])],
    policy,
    state,
    root,
  )
}

fn ask(llm, context, history, added, policy, state, root) {
  let history = list.append(history, added)
  let wait = execute.Complete(llm, context, history, added)
  use answer, state, root <- execute.Waiting(wait, state, root)
  case answer {
    execute.Completed(Ok(completion)) ->
      case completion.tool_calls {
        [] -> execute.Finished(Ok(completion.content), state, root, [])
        calls -> {
          let history = list.append(history, [chat.from_completion(completion)])
          call(llm, context, history, calls, [], policy, state, root)
        }
      }
    execute.Completed(Error(reason)) ->
      execute.Finished(Error(reason), state, root, [])
    _ -> execute.Finished(Error("expected a completion"), state, root, [])
  }
}

// Run each call in order, then ask again with their results.
fn call(llm, context, history, calls, results, policy, state, root) {
  case calls {
    [] -> ask(llm, context, history, list.reverse(results), policy, state, root)
    [tool.Call(id, tool.FunctionCall(name, arguments)), ..calls] -> {
      let next = fn(result, state, root) {
        let results = [result_to_message(id, result), ..results]
        call(llm, context, history, calls, results, policy, state, root)
      }
      case agent.cast_tool_call(name, arguments) {
        Error(reason) ->
          next(
            Error(agent.describe_failure(reason, name, arguments)),
            state,
            root,
          )
        Ok(agent.Run(code)) -> {
          use outcome, state, root, output <- execute.then(
            execute.tool(code, state, policy, root, fn(_) { Nil }),
          )
          let result = case outcome {
            Ok(text) -> Ok(tool.Return(run.report(output, text), []))
            Error(reason) -> Error(run.report(output, reason))
          }
          next(result, state, root)
        }
      }
    }
  }
}

/// History is newest-first, matching the CLI loop. Keep completed tool results
/// even if a subsequent request fails: their filesystem effects have happened.
pub fn inner_loop(
  session: Session,
  eyg_state: execute.State,
  policy: execute.Policy,
  history: chat.History,
  files: v1.Cid,
  emit: fn(execute.Output) -> Nil,
) -> #(chat.History, execute.State, v1.Cid) {
  let completion =
    provider.completion(
      session.llm,
      session.provider_context,
      list.reverse(history),
      fn(request) { continuation.return(session.fetch(request)) },
    )(fn(x) { x })
  case completion {
    Error(reason) -> {
      emit(execute.StandardError(reason))
      #(history, eyg_state, files)
    }
    Ok(completion) -> {
      case string.trim(completion.content) {
        "" -> Nil
        _ -> emit(execute.StandardOut(completion.content))
      }
      let history = [chat.from_completion(completion), ..history]
      case completion.tool_calls {
        [] -> #(history, eyg_state, files)
        calls -> {
          let #(history, eyg_state, files) =
            list.fold(calls, #(history, eyg_state, files), fn(acc, call) {
              let #(history, eyg_state, files) = acc
              let #(result, eyg_state, files) =
                execute_call(call.function, eyg_state, policy, files, emit)
              #(
                [result_to_message(call.id, result), ..history],
                eyg_state,
                files,
              )
            })
          inner_loop(session, eyg_state, policy, history, files, emit)
        }
      }
    }
  }
}

fn result_to_message(
  call_id: String,
  result: Result(tool.Return, String),
) -> chat.Message(a) {
  case result {
    Ok(tool.Return(text, images)) ->
      chat.ToolResultMessage(
        tool_call_id: call_id,
        text: agent.tool_result_text(text),
        images:,
      )
    Error(reason) ->
      chat.ToolResultMessage(
        tool_call_id: call_id,
        text: agent.tool_result_text(reason),
        images: [],
      )
  }
}

fn execute_call(call, eyg_state, policy, files, emit) {
  let tool.FunctionCall(name, arguments) = call
  case agent.cast_tool_call(name, arguments) {
    Error(reason) -> #(
      Error(agent.describe_failure(reason, name, arguments)),
      eyg_state,
      files,
    )
    Ok(agent.Run(code)) -> {
      let #(result, eyg_state, files, output) =
        execute.run(code, eyg_state, policy, files, emit)
      let result = case result {
        Ok(text) -> Ok(tool.Return(run.report(output, text), []))
        Error(reason) -> Error(run.report(output, reason))
      }
      #(result, eyg_state, files)
    }
  }
}
