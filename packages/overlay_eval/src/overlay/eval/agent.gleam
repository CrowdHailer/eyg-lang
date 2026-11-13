//// Scripted agents stand in for a model.
////
//// A scripted agent reads the conversation Overlay sends and writes the next
//// reply. Evals use them to show a task can be solved, the oracle follows a
//// reference solution, and that its graders fail when it is not, the null
//// agent never runs a program.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

pub type Conversation {
  Conversation(system: String, messages: List(Message))
}

pub type Message {
  Message(role: String, content: String, runs: List(String))
}

/// What the agent says and the programs it runs, programs run before the text
/// is final.
pub type Reply {
  Reply(text: String, runs: List(String))
}

pub type Agent =
  fn(Conversation) -> Reply

/// Decode the conversation from a chat request in the Ollama format.
pub fn conversation(body: BitArray) -> Result(Conversation, json.DecodeError) {
  let decoder = {
    use messages <- decode.field(
      "messages",
      decode.list({
        use role <- decode.field("role", decode.string)
        use content <- decode.field("content", decode.string)
        use runs <- decode.optional_field(
          "tool_calls",
          [],
          decode.list(decode.at(
            ["function", "arguments", "code"],
            decode.string,
          )),
        )
        decode.success(Message(role:, content:, runs:))
      }),
    )
    decode.success(messages)
  }
  use messages <- result.try(json.parse_bits(body, decoder))
  case messages {
    [Message(role: "system", content:, ..), ..rest] ->
      Ok(Conversation(system: content, messages: rest))
    _ -> Ok(Conversation(system: "", messages:))
  }
}

/// A completion stream in the Ollama format.
pub fn stream(reply: Reply) -> List(BitArray) {
  let Reply(text:, runs:) = reply
  let calls =
    list.map(runs, fn(code) {
      json.object([
        #(
          "function",
          json.object([
            #("name", json.string("run")),
            #("arguments", json.object([#("code", json.string(code))])),
          ]),
        ),
      ])
    })
  let message =
    json.object([
      #("role", json.string("assistant")),
      #("content", json.string(text)),
      #("tool_calls", json.preprocessed_array(calls)),
    ])
  [
    line([#("message", message), #("done", json.bool(False))]),
    line([
      #(
        "message",
        json.object([
          #("role", json.string("assistant")),
          #("content", json.string("")),
        ]),
      ),
      #("done", json.bool(True)),
    ]),
  ]
}

fn line(fields) {
  let fields = [#("model", json.string("scripted")), ..fields]
  bit_array.from_string(json.to_string(json.object(fields)) <> "\n")
}

/// Follow a script, the replies for each turn in order. A turn's last reply
/// should run nothing, it is the agent's answer.
pub fn scripted(turns: List(List(Reply))) -> Agent {
  fn(conversation: Conversation) {
    let #(turn, step) = position(conversation.messages)
    case list.drop(turns, turn) {
      [replies, ..] ->
        case list.drop(replies, step) {
          [reply, ..] -> reply
          [] -> Reply(text: "", runs: [])
        }
      [] -> Reply(text: "", runs: [])
    }
  }
}

/// Answer without running anything, a task passed by this agent does not
/// test what it claims to.
pub fn null() -> Agent {
  fn(_conversation) { Reply(text: "I can't help with that.", runs: []) }
}

/// The index of the current turn and how many replies were already given in it.
fn position(messages: List(Message)) {
  list.fold(messages, #(-1, 0), fn(acc, message) {
    let #(turn, step) = acc
    case message.role {
      "user" -> #(turn + 1, 0)
      "assistant" -> #(turn, step + 1)
      _ -> acc
    }
  })
}
