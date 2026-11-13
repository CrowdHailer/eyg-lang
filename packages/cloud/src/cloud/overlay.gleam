//// The cloud adapter for Overlay's sequential completion/tool loop.

import cloud/beam/execute
import cloud/beam/file_system
import cloud/system
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
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

pub type History =
  chat.History

pub type Complete =
  fn(History) -> Result(chat.Completion(tool.Call), String)

pub type Completer =
  fn(provider.Llm, provider.Context) -> Complete

pub fn setup(hub: origin.Origin, llm: provider.Llm) -> Session {
  let effects =
    computer.effects()
    |> policy.match_rules(execute.basic_rules)
    |> list.map(fn(rule) { rule.0 })
  let provider_context =
    provider.Context(
      system_prompt: agent.system_prompt(
        hub,
        effects,
        "context is an empty record. The working directory is /. Files belong to this session and are shared with direct code execution. Each command starts with fresh lexical scope. Env only returns secrets explicitly supplied at startup; host environment variables are not exposed. Respond using the chat platform's Markdown formatting.",
      ),
      tools: agent.tools(),
    )
  Session(llm:, provider_context:, fetch: fn(request) {
    system.fetch(request)(fn(x) { x })
  })
}

pub fn context(origin, effects, readme) -> provider.Context {
  provider.Context(
    system_prompt: agent.system_prompt(
      origin,
      effects,
      "You are part of a chat workspace. Your replies are delivered directly to the person who requested this turn. Programs run with fresh lexical scope and private in-memory session files retained between turns. Use Post when a program needs to send an additional message.\n"
        <> readme,
    ),
    tools: agent.tools(),
  )
}

pub fn complete(llm: provider.Llm, context: provider.Context) -> Complete {
  fn(history) {
    provider.completion(llm, context, list.reverse(history), system.fetch)(
      fn(x) { x },
    )
  }
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
  let complete = fn(history) {
    provider.completion(
      session.llm,
      session.provider_context,
      list.reverse(history),
      fn(request) { continuation.return(session.fetch(request)) },
    )(fn(x) { x })
  }
  let #(history, #(eyg_state, files), _) =
    complete_loop(
      history,
      complete,
      fn(code, state) {
        let #(eyg_state, files) = state
        let #(result, eyg_state, files, output) =
          execute.run(code, eyg_state, policy, files, emit)
        let result = case result {
          Ok(text) -> Ok(run.report(output, text))
          Error(reason) -> Error(run.report(output, reason))
        }
        #(result, #(eyg_state, files))
      },
      emit,
      #(eyg_state, files),
    )
  #(history, eyg_state, files)
}

/// Configured channels, delegates and main's basic agent share this loop.
pub fn complete_loop(history, complete: Complete, run_code, emit, state) {
  case complete(history) {
    Error(reason) -> {
      emit(execute.StandardError(reason))
      #(history, state, Some(reason))
    }
    Ok(completion) -> {
      case string.trim(completion.content) {
        "" -> Nil
        _ -> emit(execute.StandardOut(completion.content))
      }
      let history = [chat.from_completion(completion), ..history]
      case completion.tool_calls {
        [] -> #(history, state, None)
        calls -> {
          let #(history, state) =
            list.fold(calls, #(history, state), fn(acc, call) {
              let #(history, state) = acc
              let tool.FunctionCall(name, arguments) = call.function
              let #(result, state) = case
                agent.cast_tool_call(name, arguments)
              {
                Error(reason) -> #(
                  Error(agent.describe_failure(reason, name, arguments)),
                  state,
                )
                Ok(agent.Run(code)) -> run_code(code, state)
              }
              let text = case result {
                Ok(text) | Error(text) -> text
              }
              #(
                [
                  chat.ToolResultMessage(
                    call.id,
                    agent.tool_result_text(text),
                    [],
                  ),
                  ..history
                ],
                state,
              )
            })
          complete_loop(history, complete, run_code, emit, state)
        }
      }
    }
  }
}

/// Keep complete user turns so tool calls retain their results.
pub fn trim(history: History, max: Int) -> History {
  case list.length(history) > max {
    False -> history
    True ->
      history
      |> list.take(max)
      |> list.reverse
      |> list.drop_while(fn(message) {
        case message {
          chat.UserMessage(..) -> False
          _ -> True
        }
      })
      |> list.reverse
  }
}

pub fn last_reply(history: History) -> String {
  case history {
    [chat.AssistantMessage(text:, ..), ..] -> string.trim(text)
    _ -> ""
  }
}
