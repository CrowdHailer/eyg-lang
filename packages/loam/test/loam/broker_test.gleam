import glasshouse/store
import gleam/http/request
import gleam/http/response
import loam/broker
import loam/sandbox
import loam/system
import midas/effect

fn request() {
  let assert Ok(request) = request.to("https://example.com/status")
  request.set_body(request, <<>>)
}

pub fn repeated_requests_consume_different_observations_in_order_test() {
  let request = request()
  let first =
    broker.Exchange(
      broker.key(request),
      Ok(response.new(200) |> response.set_body(<<"pending">>)),
    )
  let second =
    broker.Exchange(
      broker.key(request),
      Ok(response.new(200) |> response.set_body(<<"done">>)),
    )
  let workflow = {
    use #(a, broker) <- system.then(broker.request(
      broker.new(broker.Replay([first, second])),
      request,
    ))
    use #(b, broker) <- system.map(broker.request(broker, request))
    #(a, b, broker)
  }
  let assert #(sandbox.Returned(#(a, b, broker)), _) =
    sandbox.run(workflow, sandbox.sandbox())
  assert a == Ok(first.reply)
  assert b == Ok(second.reply)
  assert broker.finish(broker) == Ok(Nil)
  let #(blocks, root) = broker.save(broker, store.new())
  assert broker.load(root, blocks) == Ok([first, second])
}

pub fn replay_divergence_never_falls_through_to_network_test() {
  let request = request()
  let exchange =
    broker.Exchange(
      broker.key(request),
      Ok(response.new(200) |> response.set_body(<<>>)),
    )
  let broker = broker.new(broker.Replay([exchange]))
  let assert Error(_) = broker.finish(broker)
  let changed = request.set_host(request, "other.example")
  let assert #(sandbox.Returned(#(Error(_), _)), _) =
    broker.request(broker, changed) |> sandbox.run(sandbox.sandbox())
  assert broker.key(request) != broker.key(changed)
  assert broker.key(request)
    != broker.key(request.set_header(request, "authorization", "different"))
}

pub fn divergent_fork_does_not_reuse_old_observations_test() {
  let original = request()
  let changed = request.set_path(original, "/different")
  let exchange =
    broker.Exchange(
      broker.key(original),
      Ok(response.new(200) |> response.set_body(<<"recorded">>)),
    )
  let broker = broker.new(broker.Fork([exchange], ["example.com"]))
  let host =
    sandbox.sandbox()
    |> sandbox.with_network(
      fn(request, calls) {
        #(Ok(response.new(200) |> response.set_body(<<"live">>)), [
          request.path,
          ..calls
        ])
      },
      [],
    )
  let workflow = {
    use #(_, broker) <- system.then(broker.request(broker, changed))
    broker.request(broker, original)
  }
  let assert #(sandbox.Returned(#(Ok(Ok(reply)), _)), host) =
    sandbox.run(workflow, host)
  assert reply.body == <<"live">>
  assert host.network_state == ["/status", "/different"]
}

pub fn network_failures_round_trip_without_changing_the_error_test() {
  let exchanges = [
    broker.Exchange("one", Error(effect.NetworkError("offline"))),
    broker.Exchange("two", Error(effect.UnableToReadBody)),
    broker.Exchange("three", Error(effect.NotImplemented)),
  ]
  let broker =
    broker.Broker(..broker.new(broker.Offline), observations: exchanges)
  let #(blocks, root) = broker.save(broker, store.new())
  assert broker.load(root, blocks) == Ok(broker.journal(broker))
}
