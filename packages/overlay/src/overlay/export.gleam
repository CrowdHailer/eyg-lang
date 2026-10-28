//// Export an overlay chat in the opencode session export format.
////
//// An export is `{info, messages}` where each message is `{info, parts}`.
//// Text, reasoning and tool calls are parts of a message, tool results are kept
//// in the state of the tool part of the assistant message that made the call, as opencode does.
//// Overlay does not record when each message was sent so every timestamp is the export time.

import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool

pub type Session {
  Session(
    id: String,
    directory: String,
    provider_id: String,
    model_id: String,
    /// Milliseconds since the unix epoch.
    time: Int,
  )
}

/// Encode a chat history, oldest message first.
pub fn encode(
  session: Session,
  history: List(chat.Message(tool.Call)),
) -> json.Json {
  let messages = group(history, [])
  let #(_, encoded) =
    list.fold(
      messages,
      #(Ids(message: 0, part: 0, parent: ""), []),
      fn(acc, message) {
        let #(ids, encoded) = acc
        let #(ids, message) = encode_message(session, ids, message)
        #(ids, [message, ..encoded])
      },
    )
  json.object([
    #("info", info(session, title(history))),
    #("messages", json.preprocessed_array(list.reverse(encoded))),
  ])
}

fn info(session: Session, title) {
  let Session(id:, directory:, provider_id:, model_id:, time:) = session
  json.object([
    #("id", json.string(id)),
    #("slug", json.string(slug(title))),
    #("projectID", json.string("overlay")),
    #("directory", json.string(directory)),
    #("title", json.string(title)),
    #("version", json.string("overlay")),
    #(
      "model",
      json.object([
        #("id", json.string(model_id)),
        #("providerID", json.string(provider_id)),
      ]),
    ),
    #(
      "time",
      json.object([#("created", json.int(time)), #("updated", json.int(time))]),
    ),
  ])
}

/// The first line of the first prompt.
fn title(history) {
  let first =
    list.find_map(history, fn(message) {
      case message {
        chat.UserMessage(text:, ..) -> Ok(text)
        _ -> Error(Nil)
      }
    })
  case first {
    Ok(text) -> {
      let line = case string.split_once(text, "\n") {
        Ok(#(line, _)) -> line
        Error(Nil) -> text
      }
      string.slice(line, 0, 80)
    }
    Error(Nil) -> "Overlay session"
  }
}

fn slug(title) {
  string.lowercase(title)
  |> string.to_graphemes
  |> list.map(fn(char) {
    case string.contains("abcdefghijklmnopqrstuvwxyz0123456789", char) {
      True -> char
      False -> "-"
    }
  })
  |> string.concat
  |> string.slice(0, 40)
}

type Message {
  User(text: String)
  /// The results are in the same order as the calls.
  Assistant(
    thinking: String,
    text: String,
    calls: List(#(tool.Call, Result(String, Nil))),
  )
}

/// Attach tool results to the assistant message that made the calls.
fn group(history, acc) {
  case history {
    [] -> list.reverse(acc)
    [chat.UserMessage(text:, ..), ..rest] -> group(rest, [User(text), ..acc])
    [chat.AssistantMessage(thinking:, text:, tool_calls:), ..rest] -> {
      let #(results, rest) = take_results(rest, [])
      let calls = pair_results(tool_calls, results)
      group(rest, [Assistant(thinking:, text:, calls:), ..acc])
    }
    // A result without a call is dropped.
    [chat.ToolResultMessage(..), ..rest] -> group(rest, acc)
  }
}

fn take_results(history, acc) {
  case history {
    [chat.ToolResultMessage(tool_call_id:, text:, ..), ..rest] ->
      take_results(rest, [#(tool_call_id, text), ..acc])
    _ -> #(list.reverse(acc), history)
  }
}

/// Results are matched by id, falling back to position as some providers do not give ids.
fn pair_results(calls: List(tool.Call), results) {
  let by_id =
    dict.from_list(list.filter(results, fn(r: #(String, String)) { r.0 != "" }))
  list.index_map(calls, fn(call, index) {
    let result = case dict.get(by_id, call.id) {
      Ok(text) -> Ok(text)
      Error(Nil) ->
        case list.drop(results, index) {
          [#(_, text), ..] -> Ok(text)
          [] -> Error(Nil)
        }
    }
    #(call, result)
  })
}

type Ids {
  Ids(message: Int, part: Int, parent: String)
}

fn id(prefix, n) {
  prefix <> "_" <> string.pad_start(int.to_string(n), 6, "0")
}

fn encode_message(session: Session, ids: Ids, message) {
  let message_id = id("msg", ids.message + 1)
  let ids = Ids(..ids, message: ids.message + 1)
  let time = json.int(session.time)
  case message {
    User(text:) -> {
      let #(ids, part) = text_part(session, ids, message_id, "text", text)
      let info =
        json.object([
          #("id", json.string(message_id)),
          #("sessionID", json.string(session.id)),
          #("role", json.string("user")),
          #("time", json.object([#("created", time)])),
          #("agent", json.string("overlay")),
          #(
            "model",
            json.object([
              #("providerID", json.string(session.provider_id)),
              #("modelID", json.string(session.model_id)),
            ]),
          ),
        ])
      #(
        Ids(..ids, parent: message_id),
        json.object([
          #("info", info),
          #("parts", json.preprocessed_array([part])),
        ]),
      )
    }
    Assistant(thinking:, text:, calls:) -> {
      let #(ids, reasoning) = case thinking {
        "" -> #(ids, [])
        _ -> {
          let #(ids, part) =
            text_part(session, ids, message_id, "reasoning", thinking)
          #(ids, [part])
        }
      }
      let #(ids, content) = case text {
        "" -> #(ids, [])
        _ -> {
          let #(ids, part) = text_part(session, ids, message_id, "text", text)
          #(ids, [part])
        }
      }
      let #(ids, tools) =
        list.map_fold(calls, ids, fn(ids, call) {
          tool_part(session, ids, message_id, call)
        })
      let info =
        json.object([
          #("id", json.string(message_id)),
          #("sessionID", json.string(session.id)),
          #("role", json.string("assistant")),
          #("time", json.object([#("created", time), #("completed", time)])),
          #("parentID", json.string(ids.parent)),
          #("modelID", json.string(session.model_id)),
          #("providerID", json.string(session.provider_id)),
          #("mode", json.string("overlay")),
          #("agent", json.string("overlay")),
          #(
            "path",
            json.object([
              #("cwd", json.string(session.directory)),
              #("root", json.string(session.directory)),
            ]),
          ),
          #("cost", json.int(0)),
          #(
            "tokens",
            json.object([
              #("input", json.int(0)),
              #("output", json.int(0)),
              #("reasoning", json.int(0)),
              #(
                "cache",
                json.object([#("read", json.int(0)), #("write", json.int(0))]),
              ),
            ]),
          ),
        ])
      let parts = list.flatten([reasoning, content, tools])
      #(
        ids,
        json.object([
          #("info", info),
          #("parts", json.preprocessed_array(parts)),
        ]),
      )
    }
  }
}

fn part_base(session: Session, ids: Ids, message_id, type_) {
  let part_id = id("prt", ids.part + 1)
  #(Ids(..ids, part: ids.part + 1), [
    #("id", json.string(part_id)),
    #("sessionID", json.string(session.id)),
    #("messageID", json.string(message_id)),
    #("type", json.string(type_)),
  ])
}

fn text_part(session: Session, ids, message_id, type_, text) {
  let #(ids, base) = part_base(session, ids, message_id, type_)
  let time =
    json.object([
      #("start", json.int(session.time)),
      #("end", json.int(session.time)),
    ])
  #(
    ids,
    json.object(
      list.append(base, [#("text", json.string(text)), #("time", time)]),
    ),
  )
}

fn tool_part(session: Session, ids, message_id, call) {
  let #(
    tool.Call(id: call_id, function: tool.FunctionCall(name:, arguments:)),
    result,
  ) = call
  let #(ids, base) = part_base(session, ids, message_id, "tool")
  let input = utils.fields_to_json(arguments)
  let time = json.int(session.time)
  let state = case result {
    Ok(output) ->
      json.object([
        #("status", json.string("completed")),
        #("input", input),
        #("output", json.string(output)),
        #("title", json.string(name)),
        #("metadata", json.object([])),
        #("time", json.object([#("start", time), #("end", time)])),
      ])
    Error(Nil) ->
      json.object([
        #("status", json.string("error")),
        #("input", input),
        #("error", json.string("no result was recorded")),
        #("time", json.object([#("start", time), #("end", time)])),
      ])
  }
  #(
    ids,
    json.object(
      list.append(base, [
        #("callID", json.string(call_id)),
        #("tool", json.string(name)),
        #("state", state),
      ]),
    ),
  )
}
