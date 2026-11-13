import gleam/dynamic/decode
import gleam/json
import gleam/list
import oas/generator/utils
import overlay/llm/tool

pub type Message(call) {
  UserMessage(text: String, images: List(String))
  AssistantMessage(thinking: String, text: String, tool_calls: List(call))
  ToolResultMessage(tool_call_id: String, text: String, images: List(String))
}

pub type Arguments =
  utils.Fields

pub type History =
  List(Message(tool.Call))

pub type Completion(call) {
  Completion(thinking: String, content: String, tool_calls: List(call))
}

pub fn from_completion(completion) {
  let Completion(content:, tool_calls:, thinking:) = completion
  AssistantMessage(thinking:, text: content, tool_calls:)
}

pub fn fresh() {
  Completion(thinking: "", content: "", tool_calls: [])
}

pub fn text(message) {
  case message {
    UserMessage(text:, ..) -> text
    AssistantMessage(text:, ..) -> text
    ToolResultMessage(text:, ..) -> text
  }
}

pub fn append_chunks(completion, chunks) {
  let Completion(thinking:, content:, tool_calls:) = completion
  do_append_chunks(chunks, thinking, content, tool_calls)
}

fn do_append_chunks(chunks, thinking, content, tool_calls) {
  case chunks {
    [] -> Completion(thinking:, content:, tool_calls:)
    [Completion(..) as chunk, ..rest] -> {
      do_append_chunks(
        rest,
        thinking <> chunk.thinking,
        content <> chunk.content,
        list.append(tool_calls, chunk.tool_calls),
      )
    }
  }
}

/// Encode a history, i.e. to keep a conversation across page loads.
pub fn history_to_json(history: History) -> json.Json {
  json.array(history, message_to_json)
}

fn message_to_json(message: Message(tool.Call)) -> json.Json {
  case message {
    UserMessage(text:, images:) ->
      json.object([
        #("role", json.string("user")),
        #("text", json.string(text)),
        #("images", json.array(images, json.string)),
      ])
    AssistantMessage(thinking:, text:, tool_calls:) ->
      json.object([
        #("role", json.string("assistant")),
        #("thinking", json.string(thinking)),
        #("text", json.string(text)),
        #(
          "tool_calls",
          json.array(tool_calls, fn(call: tool.Call) {
            json.object([
              #("id", json.string(call.id)),
              #("name", json.string(call.function.name)),
              #("arguments", utils.fields_to_json(call.function.arguments)),
            ])
          }),
        ),
      ])
    ToolResultMessage(tool_call_id:, text:, images:) ->
      json.object([
        #("role", json.string("tool")),
        #("tool_call_id", json.string(tool_call_id)),
        #("text", json.string(text)),
        #("images", json.array(images, json.string)),
      ])
  }
}

pub fn history_decoder() -> decode.Decoder(History) {
  decode.list(message_decoder())
}

fn message_decoder() {
  use role <- decode.field("role", decode.string)
  case role {
    "user" -> {
      use text <- decode.field("text", decode.string)
      use images <- decode.field("images", decode.list(decode.string))
      decode.success(UserMessage(text:, images:))
    }
    "assistant" -> {
      use thinking <- decode.field("thinking", decode.string)
      use text <- decode.field("text", decode.string)
      use tool_calls <- decode.field(
        "tool_calls",
        decode.list({
          use id <- decode.field("id", decode.string)
          use name <- decode.field("name", decode.string)
          use arguments <- decode.field(
            "arguments",
            decode.dict(decode.string, utils.any_decoder()),
          )
          decode.success(tool.Call(
            id:,
            function: tool.FunctionCall(name:, arguments:),
          ))
        }),
      )
      decode.success(AssistantMessage(thinking:, text:, tool_calls:))
    }
    _ -> {
      use tool_call_id <- decode.field("tool_call_id", decode.string)
      use text <- decode.field("text", decode.string)
      use images <- decode.field("images", decode.list(decode.string))
      decode.success(ToolResultMessage(tool_call_id:, text:, images:))
    }
  }
}
