//// Sessions for tests, turns are run directly and events are exported through the API.

import cloud/apex/context.{type Context, Context}
import cloud/box
import cloud/data/db
import cloud/data/sessions
import cloud/helpers
import cloud/registry
import cloud/server
import cloud/sessions/turn
import gleam/dict
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

/// A session in a new box called "home" that chats with the server, as the llm "test".
pub fn chat(context: Context, server) {
  let llms = dict.from_list([#("test", server.llm(server))])
  let context = Context(..context, llms:)
  let assert Ok(home) = box.create(context, Some("home"))
  let response =
    simulate.request(http.Post, "/boxes/" <> home.id <> "/sessions")
    |> simulate.json_body(json.object([#("llm", json.string("test"))]))
    |> helpers.dispatch(context)
  #(context, created(context, response))
}

fn created(context: Context, response) {
  let assert Ok(id) =
    json.parse(simulate.read_body(response), decode.at(["id"], decode.string))
  let assert Ok(pog.Returned(rows: [session], ..)) =
    db.execute(sessions.get(id), context.db)
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
  turn(context, session, turn.Code(code))
}

/// Send a message to the session's llm.
pub fn send(context, session, message) {
  turn(context, session, turn.Message(message))
}

fn turn(context, session, input) {
  registry.call(process(context, session), 10_000, fn(_) {
    #(Nil, turn.run(context, session, input))
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
    |> simulate.header("content-type", "application/x-ndjson")
    |> helpers.dispatch(context)
  case response.status {
    201 -> Ok(created(context, response))
    status -> Error(status)
  }
}
