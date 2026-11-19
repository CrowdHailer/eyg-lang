//// Sessions for tests, turns are run directly and events are exported through the API.

import cloud/apex/context.{type Context}
import cloud/box
import cloud/data/db
import cloud/data/sessions
import cloud/helpers
import cloud/registry
import cloud/sessions/turn
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import pog
import wisp/simulate

/// A session in a new box called "home".
pub fn session(context: Context) {
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Ok(Nil) = box.durable(context, home.id)
  let assert Ok(pog.Returned(rows: [session], ..)) =
    db.execute(sessions.create(home.id, None), context.db)
  session
}

pub fn events(context: Context, session: sessions.Session) {
  let assert Ok(history) = turn.history(context, session.id)
  list.map(history, fn(entry) { entry.2 })
}

pub fn process(context: Context, session: sessions.Session) {
  registry.lookup(context.sessions, session.id, fn() { registry.serve(Nil) })
}

pub fn run(context, session, code) {
  registry.call(process(context, session), 10_000, fn(_) {
    #(Nil, turn.run(context, session, code))
  })
}

pub fn export(context, session: sessions.Session) {
  simulate.request(http.Get, "/sessions/" <> session.id <> "/events")
  |> helpers.dispatch(context)
  |> simulate.read_body
}

/// Create a session in the box from exported events.
pub fn import_(context, box, log) {
  let response =
    simulate.request(http.Post, "/boxes/" <> box <> "/sessions")
    |> simulate.string_body(log)
    |> helpers.dispatch(context)
  case response.status {
    201 -> {
      let assert Ok(id) =
        json.parse(
          simulate.read_body(response),
          decode.at(["id"], decode.string),
        )
      let assert Ok(pog.Returned(rows: [session], ..)) =
        db.execute(sessions.get(id), context.db)
      Ok(session)
    }
    status -> Error(status)
  }
}
