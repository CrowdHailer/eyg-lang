//// A provider for any OpenAI compatible chat completions API.
////
//// This covers OpenAI, OpenRouter and local servers such as llama.cpp, vLLM or LM Studio.

import castor
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response, Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string
import oas/generator/utils
import ogre/origin
import overlay/llm/chat
import overlay/llm/requestx
import overlay/llm/tool

pub type Config {
  Config(
    origin: origin.Origin,
    /// The path of the chat completions endpoint, i.e. `/v1/chat/completions`.
    path: String,
    api_key: Option(String),
    /// Extra headers added to every request.
    headers: List(#(String, String)),
  )
}

/// Default configuration for the OpenAI API.
pub fn openai(api_key) -> Config {
  Config(
    origin: origin.https("api.openai.com"),
    path: "/v1/chat/completions",
    api_key: Some(api_key),
    headers: [],
  )
}

pub fn completion_request(config, model, system_prompt, messages, tools) {
  request(config, model, system_prompt, messages, tools, False)
}

pub fn stream_completion_request(
  config,
  model,
  system_prompt,
  messages,
  tools,
) {
  request(config, model, system_prompt, messages, tools, True)
}

fn request(config, model, system_prompt, messages, tools, stream) {
  let Config(origin:, path:, api_key:, headers:) = config
  let data = chat_request_encode(model, system_prompt, messages, tools, stream)

  origin.to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path(path)
  |> requestx.maybe(api_key, requestx.set_bearer_token)
  |> list.fold(headers, _, fn(request, header) {
    request.set_header(request, header.0, header.1)
  })
  |> requestx.set_json(data)
}

fn chat_request_encode(model, system_prompt, messages, tools, stream) {
  let messages = list.map(messages, message_encode)
  let messages = case system_prompt {
    "" -> messages
    prompt -> [
      json.object([
        #("role", json.string("system")),
        #("content", json.string(prompt)),
      ]),
      ..messages
    ]
  }
  let fields = [
    #("model", json.string(model)),
    #("messages", json.preprocessed_array(messages)),
    #("stream", json.bool(stream)),
    #("tools", json.array(tools, tool_encode)),
  ]
  json.object(
    list.append(fields, case stream {
      True -> [
        #("stream_options", json.object([#("include_usage", json.bool(True))])),
      ]
      False -> []
    }),
  )
}

fn message_encode(message: chat.Message(tool.Call)) {
  case message {
    chat.UserMessage(text:, images: _) ->
      json.object([
        #("role", json.string("user")),
        #("content", json.string(text)),
      ])
    chat.AssistantMessage(text:, tool_calls: [], ..) ->
      json.object([
        #("role", json.string("assistant")),
        #("content", json.string(text)),
      ])
    chat.AssistantMessage(text:, tool_calls:, ..) ->
      json.object([
        #("role", json.string("assistant")),
        #("content", json.string(text)),
        #("tool_calls", json.array(tool_calls, tool_call_encode)),
      ])
    chat.ToolResultMessage(tool_call_id:, text:, images: _) ->
      json.object([
        #("role", json.string("tool")),
        #("tool_call_id", json.string(tool_call_id)),
        #("content", json.string(text)),
      ])
  }
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

fn tool_call_encode(tool_call: tool.Call) {
  let tool.Call(id:, function: tool.FunctionCall(name:, arguments:)) = tool_call
  json.object([
    #("id", json.string(id)),
    #("type", json.string("function")),
    #(
      "function",
      json.object([
        #("name", json.string(name)),
        // Arguments are sent as a string of JSON
        #(
          "arguments",
          json.string(json.to_string(utils.fields_to_json(arguments))),
        ),
      ]),
    ),
  ])
}

fn tool_call_decoder() {
  use id <- decode.optional_field("id", "", decode.string)
  use function <- decode.field("function", {
    use name <- decode.optional_field("name", "", decode.string)
    use arguments <- decode.optional_field("arguments", "", decode.string)
    let decoder = decode.dict(decode.string, utils.any_decoder())
    case arguments {
      "" -> decode.success(tool.FunctionCall(name:, arguments: dict.new()))
      _ ->
        case json.parse(arguments, decoder) {
          Ok(arguments) -> decode.success(tool.FunctionCall(name:, arguments:))
          Error(_reason) ->
            decode.failure(
              tool.FunctionCall(name: "", arguments: dict.new()),
              "arguments",
            )
        }
    }
  })
  decode.success(tool.Call(id:, function:))
}

fn message_decoder() {
  use content <- decode.optional_field(
    "content",
    "",
    decode.optional(decode.string) |> decode.map(option.unwrap(_, "")),
  )
  use thinking <- decode.optional_field(
    "reasoning_content",
    "",
    decode.optional(decode.string) |> decode.map(option.unwrap(_, "")),
  )
  use tool_calls <- decode.optional_field(
    "tool_calls",
    [],
    decode.optional(decode.list(tool_call_decoder()))
      |> decode.map(option.unwrap(_, [])),
  )
  decode.success(chat.Completion(thinking:, content:, tool_calls:))
}

fn first_choice(field) {
  use choices <- decode.field(
    "choices",
    decode.list(decode.field(field, message_decoder(), decode.success)),
  )
  case choices {
    [choice, ..] -> decode.success(choice)
    [] -> decode.success(chat.fresh())
  }
}

pub fn completion_response(
  response: Response(BitArray),
) -> Result(chat.Completion(tool.Call), String) {
  case response {
    Response(status: 200, body:, ..) ->
      case json.parse_bits(body, first_choice("message")) {
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

/// Parse a stream of server sent events.
///
/// Tool call arguments are streamed as fragments of a JSON string,
/// so events are buffered until the stream is done and then joined into one completion.
pub fn completion_chunk_parse(remaining: BitArray, chunk: BitArray) {
  let buffer = <<remaining:bits, chunk:bits>>
  case bit_array.to_string(buffer) {
    Ok(text) ->
      case
        list.any(string.split(text, "\n"), fn(line) {
          string.trim(line) == "data: [DONE]"
        })
      {
        True -> #([join_events(text)], <<>>)
        False -> #([], buffer)
      }
    // A chunk can end part way through a multi byte character.
    Error(Nil) -> #([], buffer)
  }
}

type Delta {
  Delta(content: String, thinking: String, calls: List(Part))
}

type Part {
  Part(index: Int, id: String, name: String, arguments: String)
}

fn delta_decoder() {
  let text = decode.optional(decode.string) |> decode.map(option.unwrap(_, ""))
  use content <- decode.optional_field("content", "", text)
  use thinking <- decode.optional_field("reasoning_content", "", text)
  use calls <- decode.optional_field(
    "tool_calls",
    [],
    decode.optional(decode.list(part_decoder()))
      |> decode.map(option.unwrap(_, [])),
  )
  decode.success(Delta(content:, thinking:, calls:))
}

fn part_decoder() {
  use index <- decode.optional_field("index", 0, decode.int)
  use id <- decode.optional_field("id", "", decode.string)
  use #(name, arguments) <- decode.optional_field("function", #("", ""), {
    use name <- decode.optional_field("name", "", decode.string)
    use arguments <- decode.optional_field("arguments", "", decode.string)
    decode.success(#(name, arguments))
  })
  decode.success(Part(index:, id:, name:, arguments:))
}

fn event_decoder() {
  use choices <- decode.field(
    "choices",
    decode.list(decode.field("delta", delta_decoder(), decode.success)),
  )
  decode.success(choices)
}

fn join_events(text) {
  let deltas =
    string.split(text, "\n")
    |> list.flat_map(fn(line) {
      case string.trim(line) {
        "data: [DONE]" -> []
        "data:" <> event ->
          case json.parse(string.trim(event), event_decoder()) {
            Ok(deltas) -> deltas
            Error(_) -> []
          }
        _ -> []
      }
    })
  let content = list.map(deltas, fn(d: Delta) { d.content }) |> string.concat
  let thinking = list.map(deltas, fn(d: Delta) { d.thinking }) |> string.concat
  let parts = list.flat_map(deltas, fn(d: Delta) { d.calls })
  let calls =
    list.fold(parts, dict.new(), fn(calls, part: Part) {
      let #(id, name, arguments) = case dict.get(calls, part.index) {
        Ok(call) -> call
        Error(Nil) -> #("", "", "")
      }
      dict.insert(calls, part.index, #(
        id <> part.id,
        name <> part.name,
        arguments <> part.arguments,
      ))
    })
    |> dict.to_list
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(fn(entry) {
      let #(_, #(id, name, arguments)) = entry
      let decoder = decode.dict(decode.string, utils.any_decoder())
      let arguments = case json.parse(arguments, decoder) {
        Ok(arguments) -> arguments
        Error(_) -> dict.new()
      }
      tool.Call(id:, function: tool.FunctionCall(name:, arguments:))
    })
  chat.Completion(thinking:, content:, tool_calls: calls)
}
