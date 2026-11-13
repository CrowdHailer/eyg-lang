import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{Some}
import javascript/mutable_reference as ref
import otel
import otel/clock
import otel/codec
import otel/span
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/bun/streams
import plinthx/bun/subprocess
import plinthx/node/process
import simplifile

pub type Capture {
  Capture(
    server: server.Server,
    endpoint: String,
    batches: ref.MutableReference(List(#(clock.Time, List(span.Span)))),
  )
}

pub fn capture(status: Int, response: String) -> Capture {
  let batches = ref.new([])
  let assert Ok(bun) = runtime.get()
  let assert Ok(constructor) = fetch.get_response()
  let assert Ok(server) =
    server.serve(
      bun,
      server.Options(0, "127.0.0.1", fn(request) {
        let at = clock.now()
        assert fetch.request_header(request, "content-type")
          == Some("application/json")
        use body <- promise.map(fetch.request_text(request))
        let assert Ok(body) = body
        let assert Ok(spans) = json.parse(body, codec.spans())
        let _ = ref.update(batches, fn(batches) { [#(at, spans), ..batches] })
        let assert Ok(response) =
          fetch.new_response(constructor, response, status, [])
        response
      }),
    )
  Capture(
    server,
    "http://127.0.0.1:" <> int.to_string(server.port(server)),
    batches,
  )
}

pub fn spans(capture: Capture) -> List(span.Span) {
  ref.get(capture.batches)
  |> list.reverse
  |> list.flat_map(fn(batch) { batch.1 })
}

pub fn stop(capture: Capture) {
  use result <- promise.map(server.stop(capture.server, True))
  assert result == Ok(Nil)
}

pub type Result {
  Result(code: Int, stdout: String, stderr: String)
}

pub fn cli(args: List(String), env: List(#(String, String))) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(process) = process.get()
  let assert Ok(cwd) = simplifile.current_directory()
  let env =
    list.fold(
      [
        #("OTEL_EXPORTER_OTLP_ENDPOINT", ""),
        #("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", ""),
        #("OTEL_SDK_DISABLED", "false"),
        #("OTEL_SERVICE_NAME", "tracing-test"),
        #("EYG_PROFILE_FILE", ""),
        ..env
      ],
      process.env(process),
      fn(env, pair) { list.key_set(env, pair.0, pair.1) },
    )
  let assert Ok(child) =
    subprocess.spawn(
      bun,
      subprocess.Options(
        [
          "gleam",
          "run",
          "--no-print-progress",
          "--target",
          "javascript",
          "--runtime",
          "bun",
          "-m",
          "eyg_cli",
          "--",
          ..args
        ],
        cwd,
        env,
        "ignore",
        "pipe",
        "pipe",
      ),
    )
  let assert Ok(stdout) = subprocess.stdout(child)
  let assert Ok(stderr) = subprocess.stderr(child)
  let stdout = streams.to_text(bun, stdout)
  let stderr = streams.to_text(bun, stderr)
  use code <- promise.await(subprocess.exited(child))
  let assert Ok(code) = code
  use stdout <- promise.await(stdout)
  let assert Ok(stdout) = stdout
  use stderr <- promise.map(stderr)
  let assert Ok(stderr) = stderr
  Result(code, stdout, stderr)
}

pub fn find(spans: List(span.Span), name: String) -> span.Span {
  let assert Ok(found) = list.find(spans, fn(s) { s.name == name })
  found
}

pub fn verify_tree(spans: List(span.Span)) {
  assert list.length(list.unique(list.map(spans, fn(s) { s.span_id })))
    == list.length(spans)
  assert list.all(spans, fn(s) {
    assert clock.difference(s.ended, s.started) >= 0
    case s.parent_id {
      Some(parent) -> {
        let assert Ok(parent) = list.find(spans, fn(s) { s.span_id == parent })
        assert s.trace_id == parent.trace_id
        assert clock.difference(s.started, parent.started) >= 0
        assert clock.difference(parent.ended, s.ended) >= 0
      }
      _ -> Nil
    }
    True
  })
}

pub fn temporary_path() -> String {
  "/tmp/eyg-roadmap-profile-" <> otel.trace_id() <> ".json"
}
