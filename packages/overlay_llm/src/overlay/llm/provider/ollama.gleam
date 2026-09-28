import castor
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import oas/generator/utils
import ogre/origin
import overlay/llm/chat
import overlay/llm/requestx
import overlay/llm/stringx
import overlay/llm/tool

pub type Config {
  Config(origin: origin.Origin, api_key: Option(String))
}

/// Default configuration for Ollama running locally on the same machine
pub fn local() -> Config {
  Config(
    origin: origin.Origin(http.Http, "localhost", Some(11_434)),
    api_key: None,
  )
}

/// Default configuration for Ollama cloud, requires and API key.
pub fn cloud(key) -> Config {
  Config(origin: origin.https("ollama.com"), api_key: Some(key))
}

pub fn completion_request(config, model, system_prompt, messages, tools) {
  let Config(origin:, api_key:) = config
  let data = chat_request_encode(model, system_prompt, messages, tools, False)

  origin.to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path("/api/chat")
  |> requestx.maybe(api_key, requestx.set_bearer_token)
  |> requestx.set_json(data)
}

pub fn stream_completion_request(
  config,
  model,
  system_prompt,
  messages,
  tools,
) {
  let Config(origin:, api_key:) = config
  let data = chat_request_encode(model, system_prompt, messages, tools, True)

  origin.to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path("/api/chat")
  |> requestx.maybe(api_key, requestx.set_bearer_token)
  |> requestx.set_json(data)
}

fn chat_request_encode(model, system_prompt, messages, tools, stream) {
  let messages = list.map(messages, message_encode)
  let messages = case system_prompt {
    "" -> messages
    prompt -> [json_message("system", prompt, [], []), ..messages]
  }
  json.object([
    #("model", json.string(model)),
    #("messages", json.preprocessed_array(messages)),
    #("tools", json.array(tools, tool_encode)),
    #("stream", json.bool(stream)),
  ])
}

fn message_encode(message: chat.Message(tool.Call)) {
  let #(role, content, images, tool_calls) = case message {
    chat.UserMessage(text:, images:) -> #("user", text, images, [])
    chat.AssistantMessage(text:, tool_calls:, ..) -> {
      #("assistant", text, [], tool_calls)
    }
    chat.ToolResultMessage(text:, images:, ..) -> #("tool", text, images, [])
  }
  json_message(role, content, images, tool_calls)
}

fn json_message(role, content, images, tool_calls) {
  json.object([
    #("role", json.string(role)),
    #("content", json.string(content)),
    #("images", json.array(images, json.string)),
    #("tool_calls", json.array(tool_calls, tool_call_encode)),
  ])
}

pub fn tool_encode(tool) {
  let tool.Tool(name, description, parameters) = tool
  json.object([
    #("type", json.string("function")),
    #(
      "function",
      json.object([
        #("name", json.string(name)),
        #("description", json.string(description)),
        #("parameters", castor.object(parameters) |> castor.encode),
      ]),
    ),
  ])
}

pub fn completion_chunk_parse(remaining: BitArray, chunk: BitArray) {
  let assert Ok(buffer) = bit_array.to_string(<<remaining:bits, chunk:bits>>)
  let #(lines, remaining) = stringx.chunk_lines(buffer)
  let assert Ok(completion) =
    list.try_map(lines, fn(line) {
      case json.parse(line, chat_stream_event_decoder()) {
        Ok(event) -> Ok(event)
        Error(_reason) -> Error(Nil)
      }
    })
  #(completion, <<remaining:utf8>>)
}

pub fn chat_stream_event_decoder() {
  use message <- decode.field("message", message_decoder())

  decode.success(message)
}

pub fn message_decoder() {
  use content <- decode.field("content", decode.string)
  use thinking <- decode.optional_field("thinking", "", decode.string)
  use tool_calls <- decode.optional_field(
    "tool_calls",
    [],
    decode.list(tool_call_decoder()),
  )

  decode.success(chat.Completion(
    content: content,
    thinking: thinking,
    tool_calls: tool_calls,
  ))
}

pub fn tool_call_decoder() {
  use function <- decode.field("function", {
    use name <- decode.field("name", decode.string)
    use arguments <- decode.field(
      "arguments",
      decode.dict(decode.string, utils.any_decoder()),
    )
    decode.success(tool.FunctionCall(name:, arguments:))
  })
  decode.success(tool.Call(id: "", function:))
}

fn tool_call_encode(tool_call) {
  let tool.Call(function: tool.FunctionCall(name:, arguments:), ..) = tool_call
  json.object([
    #(
      "function",
      json.object([
        #("name", json.string(name)),
        #("arguments", utils.fields_to_json(arguments)),
      ]),
    ),
  ])
}
