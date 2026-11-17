//// A session runs code in a box. Every turn is recorded.

import cloud/apex/context.{type Context}
import cloud/beam/execute
import cloud/box
import cloud/box/controller.{reason, try}
import cloud/data/db
import cloud/data/sessions.{type Session, Turn}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import pog
import wisp

/// The box is made durable before the session is recorded.
pub fn create(box, context: Context) {
  use _ <- try(box.latest(context, box))
  use Nil <- try(box.durable(context, box))
  use rows <- try(run(sessions.create(box), context))
  let assert [session] = rows
  wisp.json_response(json.to_string(encode(session)), 201)
}

pub fn list(box, context: Context) {
  use rows <- try(run(sessions.list(box), context))
  wisp.json_response(json.to_string(json.array(rows, encode)), 200)
}

pub fn get(id, context: Context) {
  use session <- find(id, context)
  use turns <- try(run(sessions.turns(id), context))
  json.object([
    #("id", json.string(session.id)),
    #("box", json.string(session.box)),
    #("turns", json.array(turns, encode_turn)),
  ])
  |> json.to_string
  |> wisp.json_response(200)
}

/// File changes are kept only if the code succeeds and the box accepts them.
pub fn turn(request, id, context: Context) {
  use body <- wisp.require_json(request)
  case decode.run(body, decode.at(["code"], decode.string)) {
    Error(_) -> reason(400, "Expected code")
    Ok(code) -> {
      use session <- find(id, context)
      use start <- try(box.latest(context, session.box))
      let #(outcome, _, root, output) =
        execute.block(code, context.state, context.policy, start.root, fn(_) {
          Nil
        })
      // Code runs in this process, only the changes it made are merged into the box.
      let outcome = case outcome {
        Ok(value) if root != start.root ->
          case box.merge(context, session.box, start.root, root) {
            Ok(_) -> Ok(value)
            Error(box.Invalid(errors)) ->
              Error("File changes rejected\n" <> string.join(errors, "\n"))
            Error(box.Conflict(paths)) ->
              Error("File changes conflict\n" <> string.join(paths, "\n"))
            Error(reason) ->
              Error("File changes failed " <> string.inspect(reason))
          }
        _ -> outcome
      }
      let turn = Turn(code:, output: list.reverse(output), outcome:)
      use _ <- try(run(sessions.record_turn(id, turn), context))
      wisp.json_response(json.to_string(encode_turn(turn)), 200)
    }
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

fn encode_turn(turn: sessions.Turn) {
  json.object([
    #("code", json.string(turn.code)),
    #("output", json.array(turn.output, json.string)),
    case turn.outcome {
      Ok(value) -> #("value", json.string(value))
      Error(reason) -> #("error", json.string(reason))
    },
  ])
}
