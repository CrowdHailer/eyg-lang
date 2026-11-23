//// The entries of a chat's journal, they are enough to continue the chat.
////
//// A turn starts when a message is sent and ends when the llm replies without tool calls.
//// The code of each tool call runs in a shell made for it, see `cloud/calls`, and the chat records what each call returned.
//// A message sent while the llm's tool calls run is added to the chat after their results.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import oas/generator/utils
import overlay/agent
import overlay/llm/chat
import overlay/llm/tool

pub type Entry {
  /// A message for the llm.
  Sent(message: String)
  /// The llm's completion, recorded as soon as it is received. Its tool calls run next.
  Replied(completion: chat.Completion(tool.Call))
  /// What a tool call came to, as the llm is told it.
  Returned(call: String, result: Result(String, String))
  /// The llm could not be asked, the turn ends and the llm is told why on the next turn.
  Failed(reason: String)
  /// The turn was stopped. Tool calls that had not returned are recorded as cancelled before it.
  Cancelled
}

/// What the chat does next, from its entries.
pub type Next {
  /// The chat has replied to every message, with the llm's last reply or why the turn ended without one.
  Idle(reply: Result(String, String))
  /// The llm is asked to continue the chat.
  Ask(history: chat.History)
  /// The tool calls of the llm's last completion that have not returned.
  Call(calls: List(tool.Call))
}

pub fn next(entries: List(Entry)) -> Next {
  let #(reply, asking, pending) =
    list.fold(entries, #(Error("nothing was sent"), False, []), fn(acc, entry) {
      let #(reply, asking, pending) = acc
      case entry {
        Sent(_) -> #(reply, True, pending)
        Replied(completion) -> #(
          Ok(completion.content),
          completion.tool_calls != [],
          completion.tool_calls,
        )
        Returned(id, _) -> #(
          reply,
          asking,
          list.filter(pending, fn(call: tool.Call) { call.id != id }),
        )
        Failed(reason) -> #(Error(reason), False, [])
        Cancelled -> #(Error("cancelled"), False, [])
      }
    })
  case pending, asking {
    [_, ..], _ -> Call(pending)
    [], True -> Ask(conversation(entries))
    [], False -> Idle(reply)
  }
}

/// The messages sent to the llm and its completions, oldest first.
/// Messages sent while tool calls ran come after the calls' results.
pub fn conversation(entries: List(Entry)) -> chat.History {
  let #(history, _, _) =
    list.fold(entries, #([], [], []), fn(acc, entry) {
      let #(history, pending, held) = acc
      case entry {
        Sent(message) ->
          case pending {
            [] -> #([chat.UserMessage(message, []), ..history], pending, held)
            _ -> #(history, pending, [message, ..held])
          }
        Replied(completion) -> #(
          [chat.from_completion(completion), ..history],
          list.map(completion.tool_calls, fn(call) { call.id }),
          held,
        )
        Returned(id, result) -> {
          let text = case result {
            Ok(text) | Error(text) -> agent.tool_result_text(text)
          }
          let history = [chat.ToolResultMessage(id, text, []), ..history]
          case list.filter(pending, fn(pending) { pending != id }) {
            [] -> #(release(held, history), [], [])
            pending -> #(history, pending, held)
          }
        }
        Failed(reason) -> #(
          [
            chat.UserMessage("The last reply failed.\n" <> reason, []),
            ..release(held, history)
          ],
          [],
          [],
        )
        Cancelled -> #(
          [
            chat.UserMessage("The last reply was cancelled.", []),
            ..release(held, history)
          ],
          [],
          [],
        )
      }
    })
  list.reverse(history)
}

// Held messages are newest first, as is the history.
fn release(held, history) {
  list.fold(list.reverse(held), history, fn(history, message) {
    [chat.UserMessage(message, []), ..history]
  })
}

pub fn encode(entry: Entry) -> json.Json {
  json.object(case entry {
    Sent(message) -> [
      #("type", json.string("sent")),
      #("message", json.string(message)),
    ]
    Replied(completion) -> [
      #("type", json.string("replied")),
      #("completion", encode_completion(completion)),
    ]
    Returned(call, result) -> [
      #("type", json.string("returned")),
      #("call", json.string(call)),
      case result {
        Ok(text) -> #("value", json.string(text))
        Error(reason) -> #("error", json.string(reason))
      },
    ]
    Failed(reason) -> [
      #("type", json.string("failed")),
      #("reason", json.string(reason)),
    ]
    Cancelled -> [#("type", json.string("cancelled"))]
  })
}

pub fn decoder() -> decode.Decoder(Entry) {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "sent" -> {
      use message <- decode.field("message", decode.string)
      decode.success(Sent(message))
    }
    "replied" -> {
      use completion <- decode.field("completion", completion_decoder())
      decode.success(Replied(completion))
    }
    "returned" -> {
      use call <- decode.field("call", decode.string)
      use result <- decode.then(
        decode.one_of(decode.at(["value"], decode.string) |> decode.map(Ok), [
          decode.at(["error"], decode.string) |> decode.map(Error),
        ]),
      )
      decode.success(Returned(call, result))
    }
    "failed" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(Failed(reason))
    }
    "cancelled" -> decode.success(Cancelled)
    _ -> decode.failure(Cancelled, "Chat entry")
  }
}

fn encode_completion(completion: chat.Completion(tool.Call)) {
  json.object([
    #("thinking", json.string(completion.thinking)),
    #("content", json.string(completion.content)),
    #("tool_calls", json.array(completion.tool_calls, encode_call)),
  ])
}

fn completion_decoder() {
  use thinking <- decode.field("thinking", decode.string)
  use content <- decode.field("content", decode.string)
  use tool_calls <- decode.field("tool_calls", decode.list(call_decoder()))
  decode.success(chat.Completion(thinking:, content:, tool_calls:))
}

fn encode_call(call: tool.Call) {
  json.object([
    #("id", json.string(call.id)),
    #("name", json.string(call.function.name)),
    #("arguments", utils.fields_to_json(call.function.arguments)),
  ])
}

fn call_decoder() {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use arguments <- decode.field("arguments", utils.fields_decoder())
  decode.success(tool.Call(id, tool.FunctionCall(name, arguments)))
}
