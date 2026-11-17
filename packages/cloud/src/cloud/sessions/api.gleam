//// A session runs code in a box. Everything that happens is recorded as events.

import cloud/apex/context.{type Context}
import cloud/box
import cloud/box/controller.{reason, try}
import cloud/data/db
import cloud/data/sessions.{type Session}
import cloud/sessions/event
import cloud/sessions/trace
import cloud/sessions/turn
import eyg/ir/dag_json
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pog
import wisp

/// A session runs code, or chats with a configured llm if `{"llm": name}` is sent.
/// Events exported from another session, as JSON lines, start a session with the same history.
pub fn create(request: wisp.Request, box, context: Context) {
  use _ <- try(box.latest(context, box))
  case list.key_find(request.headers, "content-type") {
    Ok("application/x-ndjson") -> import_(request, box, context)
    _ -> start(request, box, context)
  }
}

fn start(request, box, context: Context) {
  use body <- wisp.require_bit_array_body(request)
  let decoder =
    decode.optional_field(
      "llm",
      None,
      decode.map(decode.string, Some),
      decode.success,
    )
  let llm = case body {
    <<>> -> Ok(None)
    _ -> json.parse_bits(body, decoder) |> result.replace_error(Nil)
  }
  case llm {
    Error(Nil) -> reason(400, "Expected an optional llm")
    Ok(llm) -> {
      use session <- try(turn.start(context, box, llm))
      wisp.json_response(json.to_string(encode(session)), 201)
    }
  }
}

/// Exported events are only accepted if replaying them does what they say.
fn import_(request, box, context: Context) {
  use body <- wisp.require_bit_array_body(request)
  use log <- try(
    bit_array.to_string(body)
    |> result.replace_error(Nil)
    |> result.try(parse_log)
    |> result.replace_error(box.Invalid(["Expected events as JSON lines"])),
  )
  use Nil <- try(
    turn.check(context, box, list.map(log, fn(entry) { entry.1 }))
    |> result.map_error(fn(reason) { box.Invalid([reason]) }),
  )
  let #(times, events) = list.unzip(log)
  use session <- try(turn.create(context, box, times, events))
  wisp.json_response(json.to_string(encode(session)), 201)
}

/// Every event as a line of JSON with the time it was recorded.
pub fn export(id, context: Context) {
  use history <- try(turn.history(context, id))
  history
  |> list.map(fn(entry) {
    let #(at, _, event) = entry
    json.object([#("at", json.int(at)), ..event.fields(event)])
    |> json.to_string
    <> "\n"
  })
  |> string.concat
  |> wisp.string_body(wisp.response(200), _)
  |> wisp.set_header("content-type", "application/x-ndjson")
}

/// OpenTelemetry spans for the session and each of its turns and requests, as OTLP JSON.
pub fn trace(id, context: Context) {
  use history <- try(turn.history(context, id))
  let log = list.map(history, fn(entry) { #(entry.0, entry.2) })
  trace.encode(id, trace.spans(id, log))
  |> json.to_string
  |> wisp.json_response(200)
}

fn parse_log(text) {
  string.split(text, "\n")
  |> list.filter(fn(line) { string.trim(line) != "" })
  |> list.try_map(fn(line) {
    json.parse(line, {
      use at <- decode.field("at", decode.int)
      use event <- decode.then(event.decoder())
      decode.success(#(at, event))
    })
    |> result.replace_error(Nil)
  })
}

/// A new session with the same history, both continue from it independently.
pub fn fork(id, context: Context) {
  use rows <- try(run(sessions.fork(id), context))
  case rows {
    [session] -> wisp.json_response(json.to_string(encode(session)), 201)
    _ -> reason(404, "No such session")
  }
}

pub fn list(box, context: Context) {
  use rows <- try(run(sessions.list(box), context))
  wisp.json_response(json.to_string(json.array(rows, encode)), 200)
}

pub fn get(id, context: Context) {
  use session <- find(id, context)
  use history <- try(turn.history(context, id))
  let events = list.map(history, fn(entry) { entry.2 })
  let llm = case events {
    [event.Configured(llm), ..] -> Some(llm)
    _ -> None
  }
  json.object([
    #("id", json.string(session.id)),
    #("box", json.string(session.box)),
    #("llm", json.nullable(llm, json.string)),
    #("turns", json.array(turns(events, []), encode_turn)),
  ])
  |> json.to_string
  |> wisp.json_response(200)
}

/// Each turn is run by the session's process, one at a time.
/// A turn is `{"code": code}`, `{"program": program}` with the program as DAG-JSON,
/// or `{"message": message}` for a session that chats with an llm.
pub fn turn(request, id, context: Context) {
  use body <- wisp.require_json(request)
  let decoder =
    decode.one_of(decode.at(["code"], decode.string) |> decode.map(turn.Code), [
      decode.at(["program"], dag_json.decoder(Nil)) |> decode.map(turn.Program),
      decode.at(["message"], decode.string) |> decode.map(turn.Message),
    ])
  case decode.run(body, decoder) {
    Error(_) -> reason(400, "Expected code or a message")
    Ok(input) -> {
      use session <- find(id, context)
      use #(outcome, output) <- try(turn.send(context, session, input))
      wisp.json_response(
        json.to_string(encode_turn(#(input, Some(#(outcome, output))))),
        200,
      )
    }
  }
}

/// The names of the llms a session can chat with.
pub fn llms(context: Context) {
  dict.keys(context.llms)
  |> list.sort(string.compare)
  |> json.array(json.string)
  |> json.to_string
  |> wisp.json_response(200)
}

// A turn without an outcome has not finished.
fn turns(events, acc) {
  case events, acc {
    [], _ -> list.reverse(acc)
    [event.Started(code, _), ..events], _ ->
      turns(events, [#(turn.Code(code), None), ..acc])
    [event.Submitted(program, _), ..events], _ ->
      turns(events, [#(turn.Program(program), None), ..acc])
    [event.Sent(message, _), ..events], _ ->
      turns(events, [#(turn.Message(message), None), ..acc])
    [event.Finished(outcome, output, _), ..events], [#(input, _), ..acc] ->
      turns(events, [#(input, Some(#(outcome, output))), ..acc])
    [_, ..events], _ -> turns(events, acc)
  }
}

fn find(id, context, then: fn(Session) -> wisp.Response) {
  use rows <- try(run(sessions.get(id), context))
  case rows {
    [session] -> then(session)
    _ -> reason(404, "No such session")
  }
}

fn run(query, context: Context) {
  case db.execute(query, context.db) {
    Ok(pog.Returned(rows:, ..)) -> Ok(rows)
    Error(reason) -> Error(box.Failed(string.inspect(reason)))
  }
}

fn encode(session: Session) {
  json.object([
    #("id", json.string(session.id)),
    #("box", json.string(session.box)),
  ])
}

fn encode_turn(turn) {
  let #(input, ended) = turn
  json.object([
    case input {
      turn.Code(code) -> #("code", json.string(code))
      turn.Program(program) -> #("program", dag_json.to_data_model(program))
      turn.Message(message) -> #("message", json.string(message))
    },
    ..case ended {
      None -> [#("finished", json.bool(False))]
      Some(#(outcome, output)) -> [
        #("output", json.array(output, json.string)),
        case outcome {
          Ok(value) -> #("value", json.string(value))
          Error(reason) -> #("error", json.string(reason))
        },
      ]
    }
  ])
}
