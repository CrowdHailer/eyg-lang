import example_tools as site
import gleam/fetch as client
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/javascript/promise
import gleam/option.{Some}
import gleam/string
import gleeunit
import javascript/mutable_reference as reference
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server

pub fn main() {
  gleeunit.main()
}

fn send(url, method, headers, bytes) {
  let assert Ok(request) = request.to(url)
  let request = request.Request(..request, method:, headers:, body: bytes)
  client.send_bits(request) |> promise.try_await(client.read_bytes_body)
}

pub fn static_bytes_and_model_proxy_preserve_the_http_contract_test() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(constructor) = fetch.get_response()
  let requests = reference.new(0)
  let assert Ok(upstream) =
    server.serve(
      bun,
      server.Options(0, "127.0.0.1", fn(request) {
        use body <- promise.map(fetch.request_bytes(request))
        assert body == Ok(<<0, 255, "request 🌿":utf8>>)
        assert fetch.request_method(request) == "POST"
        assert fetch.request_header(request, "x-fixture") == Some("input")
        assert string.ends_with(fetch.request_url(request), "/api/chat?q=a")
        reference.set(requests, reference.get(requests) + 1)
        let assert Ok(reply) =
          fetch.new_response(constructor, "response 🌱", 201, [
            #("x-upstream", "output"),
          ])
        reply
      }),
    )
  let origin = "http://127.0.0.1:" <> int.to_string(server.port(upstream))
  let assert Ok(local) =
    site.serve(site.Options(0, origin <> "/", origin <> "/"), [
      site.Asset("/", <<0, 1, 255>>, "application/octet-stream"),
    ])
  let url = "http://127.0.0.1:" <> int.to_string(server.port(local))
  let checked =
    {
      use reply <- promise.await(send(url <> "/", http.Get, [], <<>>))
      let assert Ok(reply) = reply
      assert reply.status == 200
      assert reply.body == <<0, 1, 255>>
      use reply <- promise.await(
        send(url <> "/api/chat?q=a", http.Post, [#("x-fixture", "input")], <<
          0, 255, "request 🌿":utf8,
        >>),
      )
      let assert Ok(reply) = reply
      assert reply.status == 201
      assert response.get_header(reply, "x-upstream") == Ok("output")
      assert reply.body == <<"response 🌱":utf8>>
      assert reference.get(requests) == 1
      use missing <- promise.map(send(url <> "/missing", http.Get, [], <<>>))
      let assert Ok(missing) = missing
      assert missing.status == 404
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use _ <- promise.await(server.stop(local, True))
  use _ <- promise.map(server.stop(upstream, True))
  let assert Ok(_) = checked
}
