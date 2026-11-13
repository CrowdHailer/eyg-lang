//// The cloud adapter for Overlay's sequential completion/tool loop.

import cloud/beam/execute
import cloud/beam/file_system
import cloud/system
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/string
import midas/continuation
import midas/effect
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
  let effects =
    computer.effects()
    |> policy.match_rules(execute.rules)
    |> list.map(fn(rule) { rule.0 })
  let provider_context =
    provider.Context(
      system_prompt: agent.system_prompt(
        hub,
        effects,
        "context is an empty record. The working directory is /. Files belong to this conversation and are shared with direct code execution. Relative imports are unavailable; use ReadFile to inspect files. Env reads configured workspace secrets and returns Some(value) or None({}) when missing. Respond using the chat platform's Markdown formatting.",
      ),
      tools: agent.tools(),
    )
  Session(llm:, provider_context:, fetch: fn(request) {
    system.fetch(request)(fn(x) { x })
  })
}

/// History is newest-first, matching the CLI loop. Keep completed tool results
/// even if a subsequent request fails: their filesystem effects have happened.
pub fn inner_loop(
  session: Session,
  eyg_state: execute.State,
  policy: execute.Policy,
  history: chat.History,
  files: file_system.State,
  emit: fn(execute.Output) -> Nil,
) -> #(chat.History, execute.State, file_system.State) {
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
