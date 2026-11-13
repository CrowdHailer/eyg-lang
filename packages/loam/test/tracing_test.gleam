import eyg/hub/cache
import eyg/interpreter/value
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import javascript/mutable_reference as ref
import loam/execute
import loam/source
import loam/system
import ogre/origin
import otel/clock
import otel/codec
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server

fn capture() {
  let spans = ref.new([])
  let assert Ok(bun) = runtime.get()
  let assert Ok(response) = fetch.get_response()
  let assert Ok(server) =
    server.serve(
      bun,
      server.Options(0, "127.0.0.1", fn(request) {
        use body <- promise.map(fetch.request_text(request))
        let assert Ok(body) = body
        let assert Ok(batch) = json.parse(body, codec.spans())
        let _ = ref.update(spans, list.append(_, batch))
        let assert Ok(response) = fetch.new_response(response, "{}", 200, [])
        response
      }),
    )
  #(
    server,
    [
      #(
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
        "http://127.0.0.1:"
          <> int.to_string(server.port(server))
          <> "/v1/traces",
      ),
    ],
    spans,
  )
}

pub fn recorded_blocks_retain_runtime_spans_and_effect_order_test() {
  let #(server, env, received) = capture()
  let assert Ok(program) =
    source.parse("let first = perform Now({}) perform Now({})", source.Inline)
  let state = execute.State(origin.https("unused.invalid"), cache.ready())
  let workflow = execute.block_recorded(program, [], state)
  use #(outcome, _, records) <- promise.await(system.run_with_environment(
    workflow,
    env,
  ))
  let assert Ok(#(Some(value.Integer(_)), _)) = outcome
  let assert [#("Now", _, value.Integer(_)), #("Now", _, value.Integer(_))] =
    records
  let spans = ref.get(received)
  let assert Ok(block) = list.find(spans, fn(span) { span.name == "eyg.eval" })
  let effects = list.filter(spans, fn(span) { span.name == "eyg.effect.Now" })
  assert list.length(effects) == 2
  assert list.all(effects, fn(span) { span.parent_id == Some(block.span_id) })
  use stopped <- promise.map(server.stop(server, True))
  assert stopped == Ok(Nil)
}

pub fn explicit_spans_are_lazy_and_close_before_the_caller_continues_test() {
  let #(server, env, received) = capture()
  let started = ref.new(False)
  let workflow =
    system.span(
      "outer",
      [#("task", "explicit")],
      fn() {
        let _ = ref.set(started, True)
        use value <- system.then(
          system.span(
            "lookup",
            [],
            fn() {
              use _ <- system.map(system.wait(5))
              42
            },
            fn(_) { Some("missing") },
          ),
        )
        system.span("recover", [], fn() { system.Done(value + 1) }, fn(_) {
          None
        })
      },
      fn(_) { None },
    )
  assert !ref.get(started)
  use result <- promise.await(system.run_with_environment(workflow, env))
  assert result == 43
  let spans = ref.get(received)
  let find = fn(name) {
    let assert Ok(span) = list.find(spans, fn(s) { s.name == name })
    span
  }
  let root = find("eyg.run")
  let outer = find("outer")
  let lookup = find("lookup")
  let recover = find("recover")
  assert list.length(spans) == 4
  assert outer.parent_id == Some(root.span_id)
  assert lookup.parent_id == Some(outer.span_id)
  assert recover.parent_id == Some(outer.span_id)
  assert clock.difference(recover.started, lookup.ended) >= 0
  assert lookup.error == Some("missing")
  assert root.error == None && outer.error == None
  use stopped <- promise.map(server.stop(server, True))
  assert stopped == Ok(Nil)
}

pub fn asynchronous_runs_keep_independent_trace_contexts_test() {
  let #(server, env, received) = capture()
  let runs =
    list.map([20, 1], fn(delay) {
      system.span(
        "wait-" <> int.to_string(delay),
        [],
        fn() {
          use _ <- system.map(system.wait(delay))
          delay
        },
        fn(_) { None },
      )
      |> system.run_with_environment(env)
    })
  use results <- promise.await(promise.await_list(runs))
  assert results == [20, 1]
  let spans = ref.get(received)
  let roots = list.filter(spans, fn(s) { s.name == "eyg.run" })
  let assert [a, b] = roots
  assert a.trace_id != b.trace_id
  assert list.all(list.filter(spans, fn(s) { s.name != "eyg.run" }), fn(s) {
    let assert Ok(root) =
      list.find(roots, fn(root) { root.trace_id == s.trace_id })
    s.parent_id == Some(root.span_id)
  })
  use stopped <- promise.map(server.stop(server, True))
  assert stopped == Ok(Nil)
}

pub fn host_exceptions_close_open_spans_and_remain_rejections_test() {
  let #(server, env, received) = capture()
  let workflow =
    system.span("failing", [], fn() { panic as "host failed" }, fn(_) { None })
  use outcome <- promise.await(
    system.run_with_environment(workflow, env)
    |> promise.map(fn(_) { Ok(Nil) })
    |> promise.rescue(fn(_) { Error(Nil) }),
  )
  assert outcome == Error(Nil)
  let spans = ref.get(received)
  assert list.length(spans) == 2
  assert list.all(spans, fn(s) { s.error != None })
  use stopped <- promise.map(server.stop(server, True))
  assert stopped == Ok(Nil)
}
