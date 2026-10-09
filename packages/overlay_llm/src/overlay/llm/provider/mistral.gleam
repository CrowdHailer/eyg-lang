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
import gleam/option.{None}
import gleam/string
import oas/generator/utils
import ogre/origin
import overlay/llm/chat
import overlay/llm/requestx
import overlay/llm/stringx
import overlay/llm/tool

pub type Config {
  Config(api_key: String)
}

const origin = origin.Origin(http.Https, "api.mistral.ai", None)

pub fn completion_request(config, model, system_prompt, messages, tools) {
  let Config(api_key:) = config
  let data = chat_request_encode(model, system_prompt, messages, tools, False)

  origin.to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path("/v1/chat/completions")
  |> requestx.set_bearer_token(api_key)
  |> requestx.set_json(data)
}

pub fn completion_response(
  response: Response(BitArray),
) -> Result(chat.Completion(tool.Call), String) {
  case response {
    Response(status: 200, body:, ..) ->
      case json.parse_bits(body, response_decoder()) {
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

fn response_decoder() {
  use choices <- decode.field(
    "choices",
    decode.list(decode.field("message", message_decoder(), decode.success)),
  )
  case choices {
    [choice, ..] -> decode.success(choice)
    [] -> decode.failure(chat.fresh(), "completion")
  }
}

fn message_decoder() {
  use content <- decode.optional_field(
    "content",
    [],
    decode.optional(content_decoder()) |> decode.map(option.unwrap(_, [])),
  )
  use tool_calls <- decode.optional_field(
    "tool_calls",
    [],
    decode.optional(decode.list(tool_call_decoder()))
      |> decode.map(option.unwrap(_, [])),
  )
  let content = string.concat(content)
  decode.success(chat.Completion(thinking: "", content:, tool_calls:))
}

pub fn stream_completion_request(
  config,
  model,
  system_prompt,
  messages,
  tools,
) {
  let Config(api_key:) = config
  let data = chat_request_encode(model, system_prompt, messages, tools, True)

  origin.to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path("/v1/chat/completions")
  |> requestx.set_bearer_token(api_key)
  |> requestx.set_json(data)
}

fn chat_request_encode(model, system_prompt, messages, tools, stream) {
  let messages = list.map(messages, message_encode)
  let messages = case system_prompt {
    "" -> messages
    prompt -> [json_message("system", [text_content(prompt)]), ..messages]
  }
  json.object([
    #("model", json.string(model)),
    #("messages", json.preprocessed_array(messages)),
    #("stream", json.bool(stream)),
    #("tools", json.array(tools, tool_encode)),
  ])
}

fn message_encode(message) {
  case message {
    chat.UserMessage(text:, images: _) ->
      json_message("user", [
        #("content", json.preprocessed_array([text_chunk(text)])),
      ])
    chat.AssistantMessage(text:, tool_calls:, ..) -> {
      json_message("assistant", [
        #("content", json.preprocessed_array([text_chunk(text)])),
        #("tool_calls", json.array(tool_calls, tool_call_encode)),
      ])
    }
    chat.ToolResultMessage(tool_call_id:, text:, images: _) ->
      json_message("tool", [
        #("tool_call_id", json.string(tool_call_id)),
        #("content", json.preprocessed_array([text_chunk(text)])),
      ])
  }
}

fn json_message(role, attributes) {
  json.object([#("role", json.string(role)), ..attributes])
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

fn content_decoder() {
  decode.one_of(decode.list(chunk_decoder()), [
    decode.string |> decode.map(list.wrap),
  ])
}

/// use when all content is text
fn text_content(text) {
  #("content", json.string(text))
}

fn chunk_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "text" -> decode.field("text", decode.string, decode.success)
    _ -> panic
  }
}

fn text_chunk(text) {
  json.object([#("type", json.string("text")), #("text", json.string(text))])
}

pub fn tool_call_decoder() {
  use id <- decode.field("id", decode.string)
  use _index <- decode.optional_field("index", 0, decode.int)
  use function <- decode.field("function", {
    use name <- decode.field("name", decode.string)
    use arguments <- decode.field("arguments", decode.string)
    let decoder = decode.dict(decode.string, utils.any_decoder())
    case json.parse(arguments, decoder) {
      Ok(arguments) -> decode.success(tool.FunctionCall(name:, arguments:))
      Error(_reason) ->
        decode.failure(
          tool.FunctionCall(name: "", arguments: dict.new()),
          "Call",
        )
    }
  })
  decode.success(tool.Call(id:, function:))
}

fn tool_call_encode(tool_call: tool.Call) {
  let tool.Call(id:, function: tool.FunctionCall(name:, arguments:)) = tool_call
  json.object([
    #("id", json.string(id)),
    #(
      "function",
      json.object([
        #("name", json.string(name)),
        #("arguments", utils.fields_to_json(arguments)),
      ]),
    ),
  ])
}

pub fn completion_chunk_parse(remaining: BitArray, chunk: BitArray) {
  let assert Ok(buffer) = bit_array.to_string(<<remaining:bits, chunk:bits>>)
  let #(lines, remaining) = stringx.chunk_lines(buffer)
  let completion =
    list.filter_map(lines, fn(line) {
      case line {
        "data: [DONE]" -> Ok(chat.fresh())
        "data:" <> event -> {
          case json.parse(string.trim(event), completion_event_decoder()) {
            Ok(event) -> Ok(event)
            Error(_reason) -> Error("Not a json payload")
          }
        }
        _ -> Error("not a data event")
      }
    })
  #(completion, <<remaining:utf8>>)
}

fn completion_event_decoder() {
  use message <- decode.then({
    use choices <- decode.field(
      "choices",
      decode.list({
        use delta <- decode.field("delta", {
          use content <- decode.optional_field("content", [], content_decoder())
          use tool_calls <- decode.optional_field(
            "tool_calls",
            [],
            decode.list(tool_call_decoder()),
          )
          let content = string.concat(content)
          decode.success(chat.Completion(thinking: "", content:, tool_calls:))
        })
        decode.success(delta)
      }),
    )
    case choices {
      [choice, ..] -> decode.success(choice)
      [] -> decode.failure(chat.fresh(), "completion")
    }
  })

  decode.success(message)
}
