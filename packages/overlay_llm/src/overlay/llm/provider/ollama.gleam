import castor
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response, Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
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
    prompt -> [json_message("system", prompt, [], [], ""), ..messages]
  }
  json.object([
    #("model", json.string(model)),
    #("messages", json.preprocessed_array(messages)),
    #("tools", json.array(tools, tool_encode)),
    #("stream", json.bool(stream)),
  ])
}

fn message_encode(message: chat.Message(tool.Call)) {
  let #(role, content, images, tool_calls, thinking) = case message {
    chat.UserMessage(text:, images:) -> #("user", text, images, [], "")
    chat.AssistantMessage(thinking:, text:, tool_calls:) -> {
      #("assistant", text, [], tool_calls, thinking)
    }
    chat.ToolResultMessage(text:, images:, ..) -> #(
      "tool",
      text,
      images,
      [],
      "",
    )
  }
  json_message(role, content, images, tool_calls, thinking)
}

fn json_message(role, content, images, tool_calls, thinking) {
  json.object([
    #("role", json.string(role)),
    #("content", json.string(content)),
    #("images", json.array(images, json.string)),
    #("tool_calls", json.array(tool_calls, tool_call_encode)),
    ..case thinking {
      "" -> []
      _ -> [#("thinking", json.string(thinking))]
    }
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

/// Each line of the stream is a JSON event.
/// An error event is returned as content so it is shown to the user.
pub fn completion_chunk_parse(remaining: BitArray, chunk: BitArray) {
  let buffer = <<remaining:bits, chunk:bits>>
  case bit_array.to_string(buffer) {
    Ok(text) -> {
      let #(lines, remaining) = stringx.chunk_lines(text)
      let completions =
        list.filter_map(lines, fn(line) {
          case json.parse(line, event_decoder()) {
            Ok(event) -> Ok(event)
            Error(_) ->
              case json.parse(line, error_decoder()) {
                Ok(reason) ->
                  Ok(
                    chat.Completion(
                      thinking: "",
                      content: "Error: " <> reason,
                      tool_calls: [],
                    ),
                  )
                Error(_) -> Error(Nil)
              }
          }
        })
      #(completions, <<remaining:utf8>>)
    }
    // A chunk can end part way through a multi byte character.
    Error(Nil) -> #([], buffer)
  }
}

fn error_decoder() {
  decode.field("error", decode.string, decode.success)
}

pub fn completion_response(
  response: Response(BitArray),
) -> Result(chat.Completion(tool.Call), String) {
  case response {
    Response(status: 200, body:, ..) ->
      case json.parse_bits(body, event_decoder()) {
        Ok(completion) -> Ok(completion)
        Error(reason) -> Error(string.inspect(reason))
      }
    Response(status:, body:, ..) ->
      Error(
        "unexpected status: "
        <> int.to_string(status)
        <> case bit_array.to_string(body) {
          Ok("") | Error(Nil) -> ""
          Ok(body) -> " " <> body
        },
      )
  }
}

/// This is used for th
pub fn event_decoder() {
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
