//// A shell runs code in a box. Everything that happens is recorded in its journal.

import cloud/apex/api
import cloud/apex/context.{type Context}
import cloud/box
import cloud/box/controller.{reason, try} as _
import cloud/data/db
import cloud/data/shells.{type Shell}
import cloud/shells/event
import cloud/shells/trace
import cloud/shells/turn
import eyg/ir/dag_json
import gleam/dynamic/decode
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import howdy/content.{type Content}
import howdy/controller
import pog

/// A shell runs code in the box, each turn after the last.
pub fn create(box, context: Context) {
  use shell <- try(turn.start(context, box))
  api.json(encode(shell), 201)
}

/// Every entry of the journal as a line of JSON with the time it was recorded.
pub fn export(id, context: Context) {
  use history <- try(turn.history(context, id))
  history
  |> list.map(fn(entry) {
    let #(at, entry) = entry
    json.object([#("at", json.int(at)), ..event.fields(entry)])
    |> json.to_string
    <> "\n"
  })
  |> string.concat
  |> content.Text
  |> response.set_body(response.new(200), _)
  |> response.set_header("content-type", "application/x-ndjson")
}

/// OpenTelemetry spans for the shell and each of its turns and requests, as OTLP JSON.
pub fn trace(id, context: Context) {
  use history <- try(turn.history(context, id))
  trace.encode(id, trace.spans(id, history))
  |> api.json(200)
}

/// A new shell with the same history, both continue from it independently.
pub fn fork(id, context: Context) {
  case turn.fork(context, id) {
    Error(box.Missing) -> reason(404, "No such shell")
    forked -> {
      use shell <- try(forked)
      api.json(encode(shell), 201)
    }
  }
}

pub fn list(box, context: Context) {
  use rows <- try(run(shells.list(box), context))
  api.json(json.array(rows, encode), 200)
}

pub fn get(id, context: Context) {
  use shell <- find(id, context)
  use history <- try(turn.history(context, id))
  let entries = list.map(history, fn(entry) { entry.1 })
  json.object([
    #("id", json.string(shell.id)),
    #("box", json.string(shell.box)),
    #("turns", json.array(turns(entries, []), encode_turn)),
  ])
  |> api.json(200)
}

/// Each turn is run by the shell's process, one at a time.
/// A turn is `{"code": code}` or `{"program": program}` with the program as DAG-JSON.
pub fn turn(request: controller.Context, id, context: Context) {
  use body <- api.read_json(request)
  let decoder =
    decode.one_of(decode.at(["code"], decode.string) |> decode.map(turn.Code), [
      decode.at(["program"], dag_json.decoder(Nil)) |> decode.map(turn.Program),
    ])
  case decode.run(body, decoder) {
    Error(_) -> reason(400, "Expected code or a program")
    Ok(input) -> {
      use shell <- find(id, context)
      use #(outcome, output) <- try(turn.send(context, shell, input))
      api.json(encode_turn(#(input, Some(#(outcome, output)))), 200)
    }
  }
}

// A turn without an outcome has not finished.
fn turns(entries, acc) {
  case entries, acc {
    [], _ -> list.reverse(acc)
    [event.Input(event.Started(code, _), ..), ..entries], _ ->
      turns(entries, [#(turn.Code(code), None), ..acc])
    [event.Input(event.Submitted(program, _), ..), ..entries], _ ->
      turns(entries, [#(turn.Program(program), None), ..acc])
    [
      event.Output(stop: event.Finished(_, output) as stop, change:, ..),
      ..entries
    ],
      [#(input, _), ..acc]
    -> {
      let outcome = turn.outcome(stop, change)
      turns(entries, [#(input, Some(#(outcome, output))), ..acc])
    }
    [event.Input(event.Cancelled, ..), ..entries], [#(input, _), ..acc] ->
      turns(entries, [#(input, Some(#(Error("cancelled"), []))), ..acc])
    [_, ..entries], _ -> turns(entries, acc)
  }
}

fn find(id, context, then: fn(Shell) -> Response(Content)) {
  use rows <- try(run(shells.get(id), context))
  case rows {
    [shell] -> then(shell)
    _ -> reason(404, "No such shell")
  }
}

fn run(query, context: Context) {
  case db.execute(query, context.db) {
    Ok(pog.Returned(rows:, ..)) -> Ok(rows)
    Error(reason) -> Error(box.Failed(string.inspect(reason)))
  }
}

fn encode(shell: Shell) {
  json.object([
    #("id", json.string(shell.id)),
    #("box", json.string(shell.box)),
  ])
}

fn encode_turn(turn) {
  let #(input, ended) = turn
  json.object([
    case input {
      turn.Code(code) -> #("code", json.string(code))
      turn.Program(program) -> #("program", dag_json.to_data_model(program))
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
