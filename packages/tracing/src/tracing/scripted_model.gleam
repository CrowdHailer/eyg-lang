//// A credential-free Ollama protocol fixture with an explicit sequence of replies.

import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import javascript/mutable_reference as reference
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server

pub type Reply {
  Run(String)
  Say(String)
}

pub type Fixture {
  Fixture(
    server: server.Server,
    origin: String,
    count: fn() -> Int,
    requests: fn() -> List(String),
  )
}

pub fn start(replies: List(Reply)) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(constructor) = fetch.get_response()
  let requests = reference.new([])
  let assert Ok(local) =
    server.serve(
      bun,
      server.Options(0, "127.0.0.1", fn(request) {
        use body <- promise.map(fetch.request_text(request))
        let assert Ok(body) = body
        let assert Ok(tools) =
          json.parse(
            body,
            decode.field(
              "tools",
              decode.list(decode.at(["function", "name"], decode.string)),
              decode.success,
            ),
          )
        assert tools == ["run"]
        let seen = reference.get(requests)
        reference.set(requests, [body, ..seen])
        let reply = case list.drop(replies, list.length(seen)) |> list.first {
          Ok(reply) -> reply
          Error(_) -> list.last(replies) |> result.unwrap(Say("Done."))
        }
        let assert Ok(response) =
          fetch.new_response(constructor, encode(reply), 200, [
            #("content-type", "application/x-ndjson"),
          ])
        response
      }),
    )
  Fixture(
    local,
    "http://127.0.0.1:" <> int.to_string(server.port(local)),
    fn() { list.length(reference.get(requests)) },
    fn() { list.reverse(reference.get(requests)) },
  )
}

fn encode(reply: Reply) {
  let #(text, calls) = case reply {
    Say(text) -> #(text, [])
    Run(code) -> #("", [
      json.object([
        #(
          "function",
          json.object([
            #("name", json.string("run")),
            #("arguments", json.object([#("code", json.string(code))])),
          ]),
        ),
      ]),
    ])
  }
  json.object([
    #(
      "message",
      json.object([
        #("role", json.string("assistant")),
        #("content", json.string(text)),
        #("tool_calls", json.preprocessed_array(calls)),
      ]),
    ),
    #("done", json.bool(True)),
  ])
  |> json.to_string
  |> string.append("\n")
}
