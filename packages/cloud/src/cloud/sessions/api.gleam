//// A session runs code in a box. Everything that happens is recorded as events.

import cloud/apex/context.{type Context}
import cloud/box
import cloud/box/controller.{reason, try}
import cloud/data/db
import cloud/data/sessions.{type Session}
import cloud/registry
import cloud/sessions/event
import cloud/sessions/turn
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import pog
import wisp

/// The box is made durable before the session is recorded.
pub fn create(box, context: Context) {
  use _ <- try(box.latest(context, box))
  use Nil <- try(box.durable(context, box))
  use rows <- try(run(sessions.create(box, None), context))
  let assert [session] = rows
  wisp.json_response(json.to_string(encode(session)), 201)
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
