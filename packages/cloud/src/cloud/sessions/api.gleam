//// A session runs code in a box. Everything that happens is recorded as events.

import cloud/apex/context.{type Context}
import cloud/box
import cloud/box/controller.{reason, try}
import cloud/data/db
import cloud/data/sessions.{type Session}
import cloud/data/thread
import cloud/registry
import cloud/sessions/event
import cloud/sessions/turn
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pog
import wisp

/// A session can be created from the events exported from another,
/// they are only accepted if replaying them does what they say.
pub fn create(request, box, context: Context) {
  use _ <- try(box.latest(context, box))
  use body <- wisp.require_bit_array_body(request)
  use log <- try(
    bit_array.to_string(body)
    |> result.replace_error(Nil)
    |> result.try(parse_log)
    |> result.replace_error(box.Invalid(["Expected events as JSON lines"])),
  )
  use Nil <- try(
    turn.check(context, list.map(log, fn(entry) { entry.1 }))
    |> result.map_error(fn(reason) { box.Invalid([reason]) }),
  )
  // The events are added to the thread, events already in it are shared.
  let payloads =
    list.map(log, fn(entry) { json.to_string(event.encode(entry.1)) })
  let nodes = thread.nodes(None, payloads)
  let head =
    list.last(nodes) |> result.map(fn(node) { node.key }) |> option.from_result
  // A box is only kept in memory until a session is made in it.
  use Nil <- try(box.durable(context, box))
  use session <- try(
    db.transaction(context.db, fn(connection) {
      let restore =
        thread.restore(list.zip(list.map(log, fn(entry) { entry.0 }), nodes))
      use _ <- result.try(db.execute(restore, connection))
      use created <- result.map(db.execute(
        sessions.create(box, head),
        connection,
      ))
      let assert [session] = created.rows
      session
    })
    |> result.map_error(fn(error) { box.Failed(string.inspect(error)) }),
  )
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

pub fn list(box, context: Context) {
  use rows <- try(run(sessions.list(box), context))
  wisp.json_response(json.to_string(json.array(rows, encode)), 200)
}

pub fn get(id, context: Context) {
  use session <- find(id, context)
  use history <- try(turn.history(context, id))
  let events = list.map(history, fn(entry) { entry.2 })
  json.object([
    #("id", json.string(session.id)),
    #("box", json.string(session.box)),
    #("turns", json.array(turns(events, []), encode_turn)),
  ])
  |> json.to_string
  |> wisp.json_response(200)
}

/// Each turn is run by the session's process, one at a time.
pub fn turn(request, id, context: Context) {
  use body <- wisp.require_json(request)
  case decode.run(body, decode.at(["code"], decode.string)) {
    Error(_) -> reason(400, "Expected code")
    Ok(code) -> {
      use session <- find(id, context)
      let process =
        registry.lookup(context.sessions, id, fn() { registry.serve(Nil) })
      use #(outcome, output) <- try(
        registry.call(process, 600_000, fn(_) {
          #(Nil, turn.run(context, session, code))
        }),
      )
      wisp.json_response(
        json.to_string(encode_turn(#(code, Some(#(outcome, output))))),
        200,
      )
    }
  }
}

// A turn without an outcome has not finished.
fn turns(events, acc) {
  case events, acc {
    [], _ -> list.reverse(acc)
    [event.Started(code, _), ..events], _ ->
      turns(events, [#(code, None), ..acc])
    [event.Finished(outcome, output, _), ..events], [#(code, _), ..acc] ->
      turns(events, [#(code, Some(#(outcome, output))), ..acc])
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
