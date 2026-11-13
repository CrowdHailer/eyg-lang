//// Development mocks for running Glasshouse without accounts, all served from one port.
////
//// - Langfuse, traces uploaded with `eyg upload` are listed at `/`.
//// - An Ollama model following a script, at `/api/chat`.
//// - A Neon database with time travel, at `/sql`.
////
//// `PORT` sets the port, default 4400.
//// `MOCK_SCRIPT` is a JSON file of rules for the model and `MOCK_NEON` a SQL file to seed the database.

import envoy
import glasshouse_mock/langfuse
import glasshouse_mock/model
import glasshouse_mock/neon
import glasshouse_mock/server
import glasshouse_mock/ui
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/time/timestamp
import simplifile

pub type State {
  State(traces: langfuse.Store, rules: List(model.Rule), database: neon.History)
}

pub fn main() -> Nil {
  let port = envoy.get("PORT") |> result.try(int.parse) |> result.unwrap(4400)
  case load(now()) {
    Ok(state) -> {
      let port = server.start(port, state, handle)
      io.println(banner(port))
    }
    Error(reason) -> io.println_error(reason)
  }
}

fn load(now) {
  use rules <- result.try(case envoy.get("MOCK_SCRIPT") {
    Ok(path) -> {
      use script <- result.try(
        simplifile.read(path)
        |> result.map_error(fn(_) { "could not read the model script " <> path }),
      )
      model.parse(script)
    }
    Error(Nil) -> Ok([])
  })
  use database <- result.try(case envoy.get("MOCK_NEON") {
    Ok(path) -> {
      use sql <- result.try(
        simplifile.read(path)
        |> result.map_error(fn(_) {
          "could not read the database seed " <> path
        }),
      )
      neon.seed(neon.new(), sql, now)
      |> result.map_error(fn(reason) {
        "seeding the database failed: " <> reason
      })
    }
    Error(Nil) -> Ok(neon.new())
  })
  Ok(State(traces: langfuse.new(), rules:, database:))
}

fn banner(port) {
  let origin = "http://localhost:" <> int.to_string(port)
  "Glasshouse mock running on " <> origin <> "
  Langfuse  LANGFUSE_HOST=" <> origin <> " LANGFUSE_PUBLIC_KEY=pk-lf-local LANGFUSE_SECRET_KEY=sk-lf-local
  Ollama    Ollama({origin: \"" <> origin <> "\", api_key: None({})})
  Neon      postgresql://demo:demo@localhost:" <> int.to_string(port) <> "/demo"
}

fn now() {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time())
  seconds * 1000 + nanoseconds / 1_000_000
}

pub fn handle(
  state: State,
  request: Request(BitArray),
  now: Int,
) -> #(State, Response(BitArray)) {
  let #(state, response) = route(state, request, now)
  #(
    state,
    response
      |> response.set_header("access-control-allow-origin", "*")
      |> response.set_header("access-control-allow-headers", "*")
      |> response.set_header(
        "access-control-allow-methods",
        "GET, POST, OPTIONS",
      ),
  )
}

fn route(state: State, request: Request(BitArray), now: Int) {
  let authorized =
    langfuse.authorized(request.get_header(request, "authorization"))
  case request.method, request.path_segments(request) {
    http.Options, _ -> #(state, response.new(204) |> response.set_body(<<>>))
    http.Post, ["api", "public", "otel", "v1", "traces"] if authorized ->
      case langfuse.ingest(state.traces, request.body) {
        Ok(#(traces, _count)) -> #(
          State(..state, traces:),
          json_response(200, json.object([])),
        )
        Error(reason) -> #(state, error(400, reason))
      }
    http.Get, ["api", "public", "traces"] if authorized -> #(
      state,
      json_response(200, langfuse.list_json(state.traces)),
    )
    http.Get, ["api", "public", "traces", id] if authorized ->
      case
        list.find(langfuse.traces(state.traces), fn(trace) { trace.id == id })
      {
        Ok(trace) -> #(
          state,
          json_response(200, langfuse.trace_json(trace, True)),
        )
        Error(Nil) -> #(state, error(404, "trace not found"))
      }
    _, ["api", "public", ..] -> #(state, error(401, "invalid credentials"))
    http.Post, ["api", "chat"] ->
      case model.reply(state.rules, request.body, now) {
        Ok(body) -> #(
          state,
          response.new(200)
            |> response.set_header("content-type", "application/json")
            |> response.set_body(<<body:utf8>>),
        )
        Error(reason) -> #(state, error(400, reason))
      }
    http.Post, ["sql"] -> {
      let #(database, response) = neon.handle(state.database, request, now)
      #(State(..state, database:), response)
    }
    http.Get, [] -> #(state, html(200, ui.traces(state.traces)))
    http.Get, ["trace", id] ->
      case
        list.find(langfuse.traces(state.traces), fn(trace) { trace.id == id })
      {
        Ok(trace) -> #(state, html(200, ui.trace(trace)))
        Error(Nil) -> #(state, html(404, ui.not_found()))
      }
    http.Get, ["neon"] -> #(state, html(200, ui.database(state.database)))
    http.Get, ["model"] -> #(state, html(200, ui.script(state.rules)))
    _, _ -> #(state, html(404, ui.not_found()))
  }
}

fn json_response(status, body) {
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(<<json.to_string(body):utf8>>)
}

fn error(status, message) {
  json_response(status, json.object([#("message", json.string(message))]))
}

fn html(status, page) {
  response.new(status)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(<<page:utf8>>)
}
