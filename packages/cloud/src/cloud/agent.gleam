//// An overlay agent on the cloud.
////
//// The agent only acts by running EYG programs with the overlay `run` tool.
//// Its text replies are kept in the conversation history but never delivered,
//// to speak in a channel it must run a program that performs `Post`.

import cloud/system
import gleam/list
import gleam/string
import ogre/origin.{type Origin}
import overlay/agent as overlay
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool
import touch_grass/interface

pub type History =
  List(chat.Message(tool.Call))

/// Request one completion for a history, histories are held newest first.
pub type Complete =
  fn(History) -> Result(chat.Completion(tool.Call), String)

/// Create the completion function for an llm, replaced in tests.
pub type Completer =
  fn(provider.Llm, provider.Context) -> Complete

/// Run a program for the agent, returning the report given back to the model.
pub type RunCode =
  fn(String) -> Result(String, String)

/// The most completions in one turn, stops an agent that never finishes.
pub const max_steps = 16

pub const instructions =
  "## Working in chat

You are part of a chat workspace.
Every message posted in a conversation you are part of is delivered to you, prefixed with where it came from and who sent it.
Messages from schedules, triggers and the workspace itself are also delivered to you.

Nothing you write as a reply is shown to anyone.
To say something in the conversation run a program that performs the `Post` effect with the text to post.

```eyg
perform Post(\"The build passed.\")
```

Post only when you have something useful to add.
It is fine to stay silent when a message is not for you or needs no answer, in that case reply with a short note for yourself and do not run Post.
"

/// The system prompt and tools for an agent with the given effects.
pub fn context(
  origin: Origin,
  effects: List(interface.Interface(a, b)),
  readme: String,
) -> provider.Context {
  provider.Context(
    system_prompt: overlay.system_prompt(
      origin,
      effects,
      instructions <> "\n" <> readme,
    ),
    tools: overlay.tools(),
  )
}

/// Complete with a provider over HTTP.
pub fn complete(llm: provider.Llm, context: provider.Context) -> Complete {
  fn(history: History) {
    provider.completion(llm, context, list.reverse(history), system.fetch)(
      fn(x) { x },
    )
  }
}

/// Add a user message and complete, running tool calls, until the agent replies without calling a tool.
pub fn turn(
  history: History,
  input: String,
  complete: Complete,
  run_code: RunCode,
) -> Result(History, String) {
  loop([chat.UserMessage(input, []), ..history], complete, run_code, max_steps)
}

fn loop(history, complete: Complete, run_code: RunCode, remaining) {
  case remaining {
    0 -> Ok(history)
    _ ->
      case complete(history) {
        Error(reason) -> Error(reason)
        Ok(completion) -> {
          let history = [chat.from_completion(completion), ..history]
          case completion.tool_calls {
            [] -> Ok(history)
            calls -> {
              let history =
                list.fold(calls, history, fn(history, call) {
                  let tool.Call(id:, function:) = call
                  [call_tool(id, function, run_code), ..history]
                })
              loop(history, complete, run_code, remaining - 1)
            }
          }
        }
      }
  }
}

fn call_tool(id, function, run_code: RunCode) {
  let tool.FunctionCall(name:, arguments:) = function
  let text = case overlay.cast_tool_call(name, arguments) {
    Ok(overlay.Run(code)) ->
      case run_code(code) {
        Ok(report) -> report
        Error(reason) -> reason
      }
    Error(reason) -> overlay.describe_failure(reason, name, arguments)
  }
  chat.ToolResultMessage(
    tool_call_id: id,
    text: overlay.tool_result_text(text),
    images: [],
  )
}

/// Keep at most `max` of the newest messages of a history.
/// The kept history starts at a user message, so tool calls keep their results.
pub fn trim(history: History, max: Int) -> History {
  case list.length(history) > max {
    False -> history
    True ->
      list.take(history, max)
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

/// The last thing the agent said, for logs.
pub fn last_reply(history: History) -> String {
  case history {
    [chat.AssistantMessage(text:, ..), ..] -> string.trim(text)
    _ -> ""
  }
}
