//// Amazon Bedrock with the Converse API, requests are signed with AWS signature version 4.
////
//// https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html

import castor
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response, Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import gleam/time/timestamp
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/requestx
import overlay/llm/sigv4
import overlay/llm/tool

pub type Config {
  Config(region: String, credentials: sigv4.Credentials)
}

pub fn completion_request(config, model, system_prompt, messages, tools) {
  completion_request_at(
    config,
    model,
    system_prompt,
    messages,
    tools,
    timestamp.system_time(),
  )
}

/// Build a deterministic request for signing checks and hosts with an injected clock.
pub fn completion_request_at(
  config,
  model,
  system_prompt,
  messages,
  tools,
  time,
) {
  let Config(region:, credentials:) = config
  let data = request_encode(system_prompt, messages, tools)

  request.new()
  |> request.set_method(http.Post)
  |> request.set_host("bedrock-runtime." <> region <> ".amazonaws.com")
  |> request.set_path("/model/" <> sigv4.encode(model) <> "/converse")
  |> requestx.set_json(data)
  |> sigv4.sign(credentials, region, "bedrock", time)
}

/// The streaming API uses the AWS event stream encoding,
/// the non streaming response is used and read once it has all arrived.
pub fn stream_completion_request(
  config,
  model,
  system_prompt,
  messages,
  tools,
) {
  completion_request(config, model, system_prompt, messages, tools)
}

fn request_encode(system_prompt, messages, tools) {
  let fields = [
    #("messages", json.preprocessed_array(encode_messages(messages))),
  ]
  let fields = case system_prompt {
    "" -> fields
    prompt -> [
      #(
        "system",
        json.preprocessed_array([json.object([#("text", json.string(prompt))])]),
      ),
      ..fields
    ]
  }
  let fields = case tools {
    [] -> fields
    tools -> [
      #("toolConfig", json.object([#("tools", json.array(tools, tool_encode))])),
      ..fields
    ]
  }
  json.object(fields)
}

/// Bedrock requires the roles to alternate, tool results are given by the user.
/// Neighbouring messages from the same role are joined.
fn encode_messages(messages: List(chat.Message(tool.Call))) {
  messages
  |> list.map(fn(message) {
    case message {
      chat.UserMessage(text:, ..) -> #("user", text_block(text))
      chat.AssistantMessage(text:, tool_calls:, ..) -> #(
        "assistant",
        list.append(text_block(text), list.map(tool_calls, tool_use_encode)),
      )
      chat.ToolResultMessage(tool_call_id:, text:, ..) -> #("user", [
        json.object([
          #(
            "toolResult",
            json.object([
              #("toolUseId", json.string(tool_call_id)),
              #(
                "content",
                json.preprocessed_array([
                  json.object([#("text", json.string(text))]),
                ]),
              ),
            ]),
          ),
        ]),
      ])
    }
  })
  |> join_roles([])
  |> list.map(fn(message) {
    let #(role, content) = message
    json.object([
      #("role", json.string(role)),
      #("content", json.preprocessed_array(content)),
    ])
  })
}

fn join_roles(messages, acc) {
  case messages, acc {
    [], _ -> list.reverse(acc)
    [#(role, content), ..rest], [#(previous, before), ..acc]
      if role == previous
    -> join_roles(rest, [#(role, list.append(before, content)), ..acc])
    [message, ..rest], _ -> join_roles(rest, [message, ..acc])
  }
}

/// Empty text blocks are rejected.
fn text_block(text) {
  case text {
    "" -> []
    _ -> [json.object([#("text", json.string(text))])]
  }
}

fn tool_use_encode(call: tool.Call) {
  let tool.Call(id:, function: tool.FunctionCall(name:, arguments:)) = call
  json.object([
    #(
      "toolUse",
      json.object([
        #("toolUseId", json.string(id)),
        #("name", json.string(name)),
        #("input", utils.fields_to_json(arguments)),
      ]),
    ),
  ])
}

pub fn tool_encode(tool) {
  let tool.Tool(name, description, parameters) = tool
  json.object([
    #(
      "toolSpec",
      json.object([
        #("name", json.string(name)),
        #("description", json.string(description)),
        #(
          "inputSchema",
          json.object([
            #("json", castor.object(parameters) |> castor.encode),
          ]),
        ),
      ]),
    ),
  ])
}

type Block {
  Text(String)
  Reasoning(String)
  ToolUse(tool.Call)
  Other
}

fn block_decoder() {
  decode.one_of(
    decode.field("text", decode.string, fn(text) { decode.success(Text(text)) }),
    [
      decode.at(["reasoningContent", "reasoningText", "text"], decode.string)
        |> decode.map(Reasoning),
      decode.field(
        "toolUse",
        {
          use id <- decode.field("toolUseId", decode.string)
          use name <- decode.field("name", decode.string)
          use arguments <- decode.field(
            "input",
            decode.dict(decode.string, utils.any_decoder()),
          )
          decode.success(
            ToolUse(tool.Call(
              id:,
              function: tool.FunctionCall(name:, arguments:),
            )),
          )
        },
        decode.success,
      ),
      decode.success(Other),
    ],
  )
}

fn response_decoder() {
  use blocks <- decode.subfield(
    ["output", "message", "content"],
    decode.list(block_decoder()),
  )
  let content =
    list.filter_map(blocks, fn(block) {
      case block {
        Text(text) -> Ok(text)
        _ -> Error(Nil)
      }
    })
    |> string.concat
  let thinking =
    list.filter_map(blocks, fn(block) {
      case block {
        Reasoning(text) -> Ok(text)
        _ -> Error(Nil)
      }
    })
    |> string.concat
  let tool_calls =
    list.filter_map(blocks, fn(block) {
      case block {
        ToolUse(call) -> Ok(call)
        _ -> Error(Nil)
      }
    })
  decode.success(chat.Completion(thinking:, content:, tool_calls:))
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

/// The whole response body is buffered until it is a complete JSON document.
pub fn completion_chunk_parse(remaining: BitArray, chunk: BitArray) {
  let buffer = <<remaining:bits, chunk:bits>>
  case json.parse_bits(buffer, response_decoder()) {
    Ok(completion) -> #([completion], <<>>)
    Error(_) -> #([], buffer)
  }
}
