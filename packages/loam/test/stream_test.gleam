import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/javascript/promise
import gleam/option.{None, Some}
import loam/sandbox
import loam/system
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server

fn body(reader, acc) {
  use chunk <- system.then(system.read_chunk(reader))
  case chunk {
    Ok(#(Some(bytes), next)) -> body(next, <<acc:bits, bytes:bits>>)
    Ok(#(None, _)) -> system.Done(Ok(acc))
    Error(reason) -> system.Done(Error(reason))
  }
}

pub fn native_stream_keeps_http_status_headers_and_body_test() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(response) = fetch.get_response()
  let assert Ok(server) =
    server.serve(
      bun,
      server.Options(0, "127.0.0.1", fn(_) {
        use _ <- promise.map(promise.resolve(Nil))
        let assert Ok(response) =
          fetch.new_response(response, "first\nsecond 🌿\n", 503, [
            #("x-fixture", "stream"),
          ])
        response
      }),
    )
  let url = "http://127.0.0.1:" <> int.to_string(server.port(server))
  let assert Ok(request) = request.to(url)
  let request = request.set_body(request, <<>>)
  let work = {
    use reply <- system.then(system.fetch_stream(request))
    let assert Ok(reply) = reply
    assert reply.status == 503
    assert response.get_header(reply, "x-fixture") == Ok("stream")
    body(reply.body, <<>>)
  }
  use read <- promise.await(system.run(work))
  assert read == Ok(<<"first\nsecond 🌿\n">>)
  use stopped <- promise.map(server.stop(server, True))
  assert stopped == Ok(Nil)
}

pub fn sandbox_streams_reuse_the_existing_network_fixture_test() {
  let assert Ok(request) = request.to("https://fixture.test/data")
  let request = request.set_body(request, <<>>)
  let reply = response.new(201) |> response.set_body(<<"payload">>)
  let computer = sandbox.sandbox() |> sandbox.save_and_return(reply)
  let effect = {
    use fetched <- system.then(system.fetch_stream(request))
    let assert Ok(reply) = fetched
    assert reply.status == 201
    body(reply.body, <<>>)
  }
  let #(outcome, computer) = sandbox.run(effect, computer)
  assert outcome == sandbox.Returned(Ok(<<"payload">>))
  assert computer.network_state == [request]
}
