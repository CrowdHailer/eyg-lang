//// Check real Fetch and Hash callbacks against an ephemeral local HTTP server.

import eyg/embed/browser
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/javascript/promise
import midas/effect
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server

pub fn main() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(response_type) = fetch.get_response()
  let assert Ok(fixture) =
    server.serve(
      bun,
      server.Options(0, "127.0.0.1", fn(_) {
        use _ <- promise.map(promise.resolve(Nil))
        let assert Ok(response) =
          fetch.new_response(response_type, "hello 🌿", 503, [
            #("x-fixture", "host"),
          ])
        response
      }),
    )
  let assert Ok(request) =
    request.to("http://127.0.0.1:" <> int.to_string(server.port(fixture)))
  let request = request.set_body(request, <<>>)
  let checked =
    {
      use reply <- promise.await(browser.send(request))
      let assert Ok(reply) = reply
      assert reply.status == 503
      assert response.get_header(reply, "x-fixture") == Ok("host")
      assert reply.body == <<"hello 🌿":utf8>>
      use reply <- promise.map(browser.fetch(request)(promise.resolve))
      let assert Ok(reply) = reply
      assert reply.status == 503
      assert reply.body == <<"hello 🌿":utf8>>
      Nil
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use stopped <- promise.await(server.stop(fixture, True))
  assert stopped == Ok(Nil)
  let assert Ok(_) = checked
  use failed <- promise.map(browser.send(request))
  let assert Error(effect.NetworkError(_)) = failed
  io.println(
    "PASS native fetch status, headers, UTF-8 body and network failure",
  )
}
