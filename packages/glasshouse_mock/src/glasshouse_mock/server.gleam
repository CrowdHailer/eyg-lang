//// Bun serves HTTP; request adaptation and sequential mock state are Gleam.

import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/javascript/promise
import gleam/option.{Some}
import gleam/result
import gleam/uri
import javascript/mutable_reference as reference
import otel/clock
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server

pub fn start(port, initial, handler) -> Int {
  let assert Ok(server) = start_server(port, initial, handler)
  server.port(server)
}

pub fn start_server(
  port: Int,
  initial: state,
  handler: fn(state, request.Request(BitArray), Int) ->
    #(state, response.Response(BitArray)),
) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(constructor) = fetch.get_response()
  let state = reference.new(initial)
  server.serve(
    bun,
    server.Options(port, "127.0.0.1", fn(incoming) {
      use body <- promise.map(fetch.request_bytes(incoming))
      let assert Ok(body) = body
      let assert Ok(uri) = uri.parse(fetch.request_url(incoming))
      let request =
        request.Request(
          method: http.parse_method(fetch.request_method(incoming))
            |> result.unwrap(http.Get),
          headers: fetch.request_headers(incoming),
          body:,
          scheme: http.Http,
          host: "localhost",
          port: Some(port),
          path: uri.path,
          query: uri.query,
        )
      let time = clock.now()
      let now = time.seconds * 1000 + time.nanoseconds / 1_000_000
      let #(next, reply) = handler(reference.get(state), request, now)
      let _ = reference.set(state, next)
      let assert Ok(response) = case reply.status {
        204 | 205 | 304 ->
          fetch.new_empty_response(constructor, reply.status, reply.headers)
        _ ->
          fetch.new_response_bits(
            constructor,
            reply.body,
            reply.status,
            reply.headers,
          )
      }
      response
    }),
  )
}
