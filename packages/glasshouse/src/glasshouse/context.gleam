//// The context an agent had at any point in a session.
////
//// `before` reconstructs the conversation from the session's events.
//// `from_request` reads the exact messages sent in a recorded generation request.

import glasshouse/session.{type Session}
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub type Message {
  System(text: String)
  User(text: String)
  Assistant(thinking: String, text: String, tool_calls: List(session.ToolCall))
  Tool(call_id: String, text: String)
}

/// The messages the model would see if asked for a completion before the event at `index`.
/// A failed generation discards the prompt that caused it, as the CLI does.
pub fn before(session: Session, index: Int) -> List(Message) {
  let system = case session.agent {
    Some(agent) -> [System(agent.system_prompt)]
    None -> []
  }
  let #(messages, _) =
    session.events
    |> list.take(index)
    |> list.fold(#(list.reverse(system), list.reverse(system)), fn(acc, event) {
      let #(messages, checkpoint) = acc
      case event {
        session.Prompt(text:, ..) -> #([User(text), ..messages], messages)
        session.Generated(generation:) ->
          case generation.error {
            Some(_) -> #(checkpoint, checkpoint)
            None -> #(
              [
                Assistant(
                  generation.thinking,
                  generation.content,
                  generation.tool_calls,
                ),
                ..messages
              ],
              checkpoint,
            )
          }
        session.ToolResult(call_id:, text:, ..) -> #(
          [Tool(call_id, text), ..messages],
          checkpoint,
        )
        session.Execution(..) -> acc
      }
    })
  list.reverse(messages)
}

/// The messages in a chat completion request body, as sent to the provider.
/// Both the Ollama and Mistral request formats are understood.
pub fn from_request(body: BitArray) -> Result(List(Message), String) {
  use text <- result.try(
    bit_array.to_string(body) |> result.replace_error("request is not text"),
  )
  json.parse(
    text,
    decode.field("messages", decode.list(message_decoder()), decode.success),
  )
  |> result.replace_error("request has no messages")
}

fn message_decoder() {
  use role <- decode.field("role", decode.string)
  use content <- decode.optional_field(
    "content",
    "",
    decode.optional(decode.string) |> decode.map(option.unwrap(_, "")),
  )
  use thinking <- decode.optional_field("thinking", "", decode.string)
  use tool_calls <- decode.optional_field(
    "tool_calls",
    [],
    decode.list(tool_call_decoder()),
  )
  use call_id <- decode.optional_field("tool_call_id", "", decode.string)
  case role {
    "system" -> decode.success(System(content))
    "user" -> decode.success(User(content))
    "assistant" -> decode.success(Assistant(thinking, content, tool_calls))
    _ -> decode.success(Tool(call_id, content))
  }
}

fn tool_call_decoder() {
  use id <- decode.optional_field("id", "", decode.string)
  use #(name, arguments) <- decode.field("function", {
    use name <- decode.field("name", decode.string)
    use arguments <- decode.optional_field(
      "arguments",
      "",
      decode.one_of(decode.string, [
        // Ollama sends arguments as an object, the run tool only has string arguments.
        decode.dict(decode.string, decode.string)
          |> decode.map(fn(fields) {
            dict.to_list(fields)
            |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
            |> list.map(fn(field) { #(field.0, json.string(field.1)) })
            |> json.object
            |> json.to_string
          }),
        decode.success("{...}"),
      ]),
    )
    decode.success(#(name, arguments))
  })
  decode.success(session.ToolCall(id:, name:, arguments:))
}
