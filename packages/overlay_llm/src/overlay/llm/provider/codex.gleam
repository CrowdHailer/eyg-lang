//// Use a ChatGPT subscription through the Codex backend.
////
//// Requests use the Responses API and the response is always a stream of server sent events.
//// The access token and account id are found in `~/.codex/auth.json` after logging in with the Codex CLI.
//// This endpoint is not a documented public API and may change.

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
import gleam/result
import gleam/string
import oas/generator/utils
import ogre/origin
import overlay/llm/chat
import overlay/llm/requestx
import overlay/llm/tool

pub type Config {
  Config(access_token: String, account_id: String)
}

const path = "/backend-api/codex/responses"

pub fn completion_request(config, model, system_prompt, messages, tools) {
  let Config(access_token:, account_id:) = config
  let data = request_encode(model, system_prompt, messages, tools)

  origin.to_request(origin.https("chatgpt.com"))
  |> request.set_method(http.Post)
  |> request.set_path(path)
  |> requestx.set_bearer_token(access_token)
  |> request.set_header("chatgpt-account-id", account_id)
  |> request.set_header("openai-beta", "responses=experimental")
  |> request.set_header("originator", "codex_cli_rs")
  |> request.set_header("accept", "text/event-stream")
  |> requestx.set_json(data)
}

/// The Codex backend only streams, so both requests are the same.
pub fn stream_completion_request(
  config,
  model,
  system_prompt,
  messages,
  tools,
) {
  completion_request(config, model, system_prompt, messages, tools)
}

fn request_encode(model, system_prompt, messages, tools) {
  json.object([
    #("model", json.string(model)),
    #("instructions", json.string(system_prompt)),
    #("input", json.preprocessed_array(list.flat_map(messages, input_items))),
    #("tools", json.array(tools, tool_encode)),
    #("tool_choice", json.string("auto")),
    #("parallel_tool_calls", json.bool(False)),
    #("store", json.bool(False)),
    #("stream", json.bool(True)),
  ])
}

fn input_items(message: chat.Message(tool.Call)) -> List(json.Json) {
  case message {
    chat.UserMessage(text:, images: _) -> [
      message_item("user", "input_text", text),
    ]
    chat.AssistantMessage(text:, tool_calls:, ..) -> {
      let calls = list.map(tool_calls, function_call_item)
      case text {
        "" -> calls
        _ -> [message_item("assistant", "output_text", text), ..calls]
      }
    }
    chat.ToolResultMessage(tool_call_id:, text:, images: _) -> [
      json.object([
        #("type", json.string("function_call_output")),
        #("call_id", json.string(tool_call_id)),
        #("output", json.string(text)),
      ]),
    ]
  }
}

fn message_item(role, kind, text) {
  json.object([
    #("type", json.string("message")),
    #("role", json.string(role)),
    #(
      "content",
      json.preprocessed_array([
        json.object([#("type", json.string(kind)), #("text", json.string(text))]),
      ]),
    ),
  ])
}

fn function_call_item(call: tool.Call) {
  let tool.Call(id:, function: tool.FunctionCall(name:, arguments:)) = call
  json.object([
    #("type", json.string("function_call")),
    #("call_id", json.string(id)),
    #("name", json.string(name)),
    #("arguments", json.string(json.to_string(utils.fields_to_json(arguments)))),
  ])
}

pub fn tool_encode(tool) {
  let tool.Tool(name, description, parameters) = tool
  json.object([
    #("type", json.string("function")),
    #("name", json.string(name)),
    #("description", json.string(description)),
    #("strict", json.bool(False)),
    #("parameters", castor.object(parameters) |> castor.encode),
  ])
}

pub fn completion_response(
  response: Response(BitArray),
) -> Result(chat.Completion(tool.Call), String) {
  case response {
    Response(status: 200, body:, ..) ->
      case bit_array.to_string(body) {
        Ok(text) -> events_to_completion(text)
        Error(Nil) -> Error("response is not valid utf-8")
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

/// Events are buffered until the response is complete, then joined into one completion.
pub fn completion_chunk_parse(remaining: BitArray, chunk: BitArray) {
  let buffer = <<remaining:bits, chunk:bits>>
  case bit_array.to_string(buffer) {
    Ok(text) ->
      case events_to_completion(text) {
        Ok(completion) -> #([completion], <<>>)
        Error(_) -> #([], buffer)
      }
    Error(Nil) -> #([], buffer)
  }
}

type Event {
  ItemDone(Item)
  Completed(Option(List(Item)))
  Failed(String)
  Other
}

type Item {
  Message(text: String)
  FunctionCall(call_id: String, name: String, arguments: String)
  Reasoning(text: String)
  OtherItem
}

fn event_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "response.output_item.done" ->
      decode.field("item", item_decoder(), fn(item) {
        decode.success(ItemDone(item))
      })
    "response.completed" ->
      decode.optional_field(
        "response",
        None,
        decode.optional_field(
          "output",
          None,
          decode.list(item_decoder()) |> decode.map(Some),
          decode.success,
        ),
        fn(items) { decode.success(Completed(items)) },
      )
    "response.incomplete" ->
      decode.one_of(
        decode.at(["response", "incomplete_details", "reason"], decode.string),
        [decode.success("response incomplete")],
      )
      |> decode.map(fn(reason) { Failed("response incomplete: " <> reason) })
    "response.failed" ->
      decode.one_of(decode.at(["response", "error", "message"], decode.string), [
        decode.success("response failed"),
      ])
      |> decode.map(Failed)
    "error" ->
      decode.optional_field("message", "error", decode.string, fn(message) {
        decode.success(Failed(message))
      })
    _ -> decode.success(Other)
  }
}

fn text_parts(field) {
  decode.optional_field(
    field,
    "",
    decode.list(decode.optional_field("text", "", decode.string, decode.success))
      |> decode.map(string.concat),
    decode.success,
  )
}

fn item_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "message" -> text_parts("content") |> decode.map(Message)
    "reasoning" -> text_parts("summary") |> decode.map(Reasoning)
    "function_call" -> {
      use call_id <- decode.field("call_id", decode.string)
      use name <- decode.field("name", decode.string)
      use arguments <- decode.field("arguments", decode.string)
      decode.success(FunctionCall(call_id:, name:, arguments:))
    }
    _ -> decode.success(OtherItem)
  }
}

fn events_to_completion(text) {
  let events =
    string.split(text, "\n")
    |> list.filter_map(fn(line) {
      case string.trim(line) {
        "data:" <> data ->
          json.parse(string.trim(data), event_decoder())
          |> result.replace_error(Nil)
        _ -> Error(Nil)
      }
    })
  case list.find_map(events, failure) {
    Ok(reason) -> Error(reason)
    Error(Nil) -> {
      let completed =
        events
        |> list.filter_map(fn(event) {
          case event {
            Completed(items) -> Ok(items)
            _ -> Error(Nil)
          }
        })
        |> list.last
      use items <- result.try(case completed {
        Error(Nil) -> Error("response stream ended before response.completed")
        Ok(Some(items)) -> Ok(items)
        Ok(None) ->
          Ok(
            list.filter_map(events, fn(event) {
              case event {
                ItemDone(item) -> Ok(item)
                _ -> Error(Nil)
              }
            }),
          )
      })
      use tool_calls <- result.map(
        list.filter_map(items, fn(item) {
          case item {
            FunctionCall(call_id:, name:, arguments:) ->
              Ok(#(call_id, name, arguments))
            _ -> Error(Nil)
          }
        })
        |> list.try_map(fn(call) {
          let #(id, name, arguments) = call
          let decoder = decode.dict(decode.string, utils.any_decoder())
          case json.parse(arguments, decoder) {
            Ok(arguments) ->
              Ok(tool.Call(id:, function: tool.FunctionCall(name:, arguments:)))
            Error(_) -> Error("invalid arguments for tool call " <> name)
          }
        }),
      )
      let content =
        list.filter_map(items, fn(item) {
          case item {
            Message(text) -> Ok(text)
            _ -> Error(Nil)
          }
        })
        |> string.concat
      let thinking =
        list.filter_map(items, fn(item) {
          case item {
            Reasoning(text) -> Ok(text)
            _ -> Error(Nil)
          }
        })
        |> string.concat
      chat.Completion(thinking:, content:, tool_calls:)
    }
  }
}

fn failure(event) {
  case event {
    Failed(reason) -> Ok(reason)
    _ -> Error(Nil)
  }
}
