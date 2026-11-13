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
/// Chat Completions, Ollama, Bedrock Converse and Responses request formats.
pub fn from_request(body: BitArray) -> Result(List(Message), String) {
  use text <- result.try(
    bit_array.to_string(body) |> result.replace_error("request is not text"),
  )
  json.parse(
    text,
    decode.one_of(
      decode.field("messages", decode.list(message_decoder()), decode.success),
      [bedrock_request_decoder(), responses_request_decoder()],
    ),
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

type BedrockBlock {
  TextBlock(String)
  CallBlock(session.ToolCall)
  ResultBlock(String, String)
  OtherBlock
}

fn bedrock_request_decoder() {
  use system <- decode.optional_field(
    "system",
    [],
    decode.list(decode.field("text", decode.string, decode.success)),
  )
  use messages <- decode.field(
    "messages",
    decode.list({
      use role <- decode.field("role", decode.string)
      use blocks <- decode.field(
        "content",
        decode.list(bedrock_block_decoder()),
      )
      let messages = case role {
        "assistant" -> {
          let text =
            list.filter_map(blocks, fn(block) {
              case block {
                TextBlock(text) -> Ok(text)
                _ -> Error(Nil)
              }
            })
            |> string.concat
          let calls =
            list.filter_map(blocks, fn(block) {
              case block {
                CallBlock(call) -> Ok(call)
                _ -> Error(Nil)
              }
            })
          [Assistant("", text, calls)]
        }
        _ ->
          list.filter_map(blocks, fn(block) {
            case block {
              TextBlock(text) -> Ok(User(text))
              ResultBlock(id, text) -> Ok(Tool(id, text))
              _ -> Error(Nil)
            }
          })
      }
      decode.success(messages)
    }),
  )
  decode.success(list.append(list.map(system, System), list.flatten(messages)))
}

fn bedrock_block_decoder() {
  decode.one_of(
    decode.field("text", decode.string, decode.success) |> decode.map(TextBlock),
    [
      decode.field(
        "toolUse",
        {
          use id <- decode.field("toolUseId", decode.string)
          use name <- decode.field("name", decode.string)
          use fields <- decode.field(
            "input",
            decode.dict(decode.string, decode.string),
          )
          let arguments =
            dict.to_list(fields)
            |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
            |> list.map(fn(field) { #(field.0, json.string(field.1)) })
            |> json.object
            |> json.to_string
          decode.success(CallBlock(session.ToolCall(id:, name:, arguments:)))
        },
        decode.success,
      ),
      decode.field(
        "toolResult",
        {
          use id <- decode.field("toolUseId", decode.string)
          use content <- decode.field(
            "content",
            decode.list(decode.field("text", decode.string, decode.success)),
          )
          decode.success(ResultBlock(id, string.concat(content)))
        },
        decode.success,
      ),
      decode.success(OtherBlock),
    ],
  )
}

fn responses_request_decoder() {
  use instructions <- decode.optional_field("instructions", "", decode.string)
  use items <- decode.field(
    "input",
    decode.list({
      use type_ <- decode.optional_field("type", "message", decode.string)
      case type_ {
        "message" -> {
          use role <- decode.field("role", decode.string)
          use parts <- decode.field(
            "content",
            decode.list(decode.optional_field(
              "text",
              "",
              decode.string,
              decode.success,
            )),
          )
          let text = string.concat(parts)
          decode.success(
            Some(case role {
              "assistant" -> Assistant("", text, [])
              "system" | "developer" -> System(text)
              _ -> User(text)
            }),
          )
        }
        "function_call" -> {
          use id <- decode.field("call_id", decode.string)
          use name <- decode.field("name", decode.string)
          use arguments <- decode.field("arguments", decode.string)
          decode.success(
            Some(Assistant("", "", [session.ToolCall(id:, name:, arguments:)])),
          )
        }
        "function_call_output" -> {
          use id <- decode.field("call_id", decode.string)
          use text <- decode.field("output", decode.string)
          decode.success(Some(Tool(id, text)))
        }
        _ -> decode.success(None)
      }
    }),
  )
  let items = list.filter_map(items, option.to_result(_, Nil))
  let messages =
    list.fold(items, [], fn(acc, item) {
      case item, acc {
        Assistant(thinking, text, calls),
          [Assistant(before_thinking, before_text, before_calls), ..rest]
        -> [
          Assistant(
            before_thinking <> thinking,
            before_text <> text,
            list.append(before_calls, calls),
          ),
          ..rest
        ]
        _, _ -> [item, ..acc]
      }
    })
    |> list.reverse
  let system = case instructions {
    "" -> []
    _ -> [System(instructions)]
  }
  decode.success(list.append(system, messages))
}
