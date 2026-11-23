//// A shell runs code in a box. Everything that happens is recorded in its journal.

import cloud/apex/api
import cloud/apex/context.{type Context}
import cloud/box
import cloud/box/controller.{reason, try} as _
import cloud/data/db
import cloud/data/shells.{type Shell}
import cloud/registry
import cloud/shells/event
import cloud/shells/turn
import gleam/dynamic/decode
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import howdy/content.{type Content}
import howdy/controller
import pog

pub fn create(box, context: Context) {
  use _ <- try(box.latest(context, box))
  use rows <- try(run(shells.create(box), context))
  let assert [shell] = rows
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
pub fn turn(request: controller.Context, id, context: Context) {
  use body <- api.read_json(request)
  case decode.run(body, decode.at(["code"], decode.string)) {
    Error(_) -> reason(400, "Expected code")
    Ok(code) -> {
      use shell <- find(id, context)
      let process =
        registry.lookup(context.shells, id, fn() { registry.serve(Nil) })
      use #(outcome, output) <- try(
        registry.call(process, 600_000, fn(_) {
          #(Nil, turn.run(context, shell, code))
        }),
      )
      api.json(encode_turn(#(code, Some(#(outcome, output)))), 200)
    }
  }
}

// A turn without an outcome has not finished.
fn turns(entries, acc) {
  case entries, acc {
    [], _ -> list.reverse(acc)
    [event.Input(event.Started(code, _), ..), ..entries], _ ->
      turns(entries, [#(code, None), ..acc])
    [
      event.Output(stop: event.Finished(_, output) as stop, change:, ..),
      ..entries
    ],
      [#(input, _), ..acc]
    -> {
      let outcome = turn.outcome(stop, change)
      turns(entries, [#(input, Some(#(outcome, output))), ..acc])
    }
    // A rejected change finishes the turn.
    [event.Output(change: event.Rejected(reason), ..), ..entries],
      [#(input, _), ..acc]
    -> turns(entries, [#(input, Some(#(Error(reason), []))), ..acc])
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
  let #(code, ended) = turn
  json.object([
    #("code", json.string(code)),
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
