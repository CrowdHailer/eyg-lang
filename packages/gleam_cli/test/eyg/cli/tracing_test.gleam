import eyg/cli/tracing_helpers as h
import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import javascript/mutable_reference as ref
import simplifile

pub fn cli_exports_nested_evaluation_and_effect_spans_test() {
  let capture = h.capture(200, "{}")
  use result <- promise.await(
    h.cli(["run", "-c", "perform StandardOut(\"hello\")"], [
      #("OTEL_EXPORTER_OTLP_ENDPOINT", capture.endpoint),
    ]),
  )
  assert result == h.Result(0, "hello", "")
  let all = h.spans(capture)
  h.verify_tree(all)
  assert list.length(all) == 3
  let root = h.find(all, "eyg.run")
  let eval = h.find(all, "eyg.eval")
  let effect = h.find(all, "eyg.effect.StandardOut")
  assert eval.parent_id == Some(root.span_id)
  assert effect.parent_id == Some(eval.span_id)
  assert list.all(all, fn(s) { s.error == None })
  h.stop(capture)
}

pub fn runtime_failure_and_exit_flush_open_spans_test() {
  let capture = h.capture(200, "{}")
  use result <- promise.await(
    h.cli(["run", "-c", "perform Abort(\"failed task\")"], [
      #(
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
        capture.endpoint <> "/custom-traces",
      ),
    ]),
  )
  assert result.code == 1 && string.contains(result.stderr, "failed task")
  assert h.find(h.spans(capture), "eyg.run").error != None
  assert h.find(h.spans(capture), "eyg.eval").error != None
  use _ <- promise.await(h.stop(capture))
  let capture = h.capture(200, "{}")
  use result <- promise.await(
    h.cli(["run", "-c", "perform Exit(7)"], [
      #("OTEL_EXPORTER_OTLP_ENDPOINT", capture.endpoint),
    ]),
  )
  assert result.code == 7
  assert list.length(h.spans(capture)) == 3
  assert list.all(h.spans(capture), fn(s) { s.error != None })
  h.stop(capture)
}

pub fn returned_effect_errors_do_not_fail_the_caller_test() {
  let capture = h.capture(200, "{}")
  use result <- promise.await(
    h.cli(
      [
        "run",
        "-c",
        "perform ReadFile({path: \"/eyg-tracing-missing/file\", offset: 0, limit: 1})",
      ],
      [#("OTEL_EXPORTER_OTLP_ENDPOINT", capture.endpoint)],
    ),
  )
  assert result.code == 0
  assert h.find(h.spans(capture), "eyg.run").error == None
  assert h.find(h.spans(capture), "eyg.eval").error == None
  assert h.find(h.spans(capture), "eyg.effect.ReadFile").error != None
  h.stop(capture)
}

pub fn collector_failures_and_partial_rejection_preserve_exit_status_test() {
  let capture = h.capture(503, "{}")
  use result <- promise.await(
    h.cli(["run", "-c", "42"], [
      #("OTEL_EXPORTER_OTLP_ENDPOINT", capture.endpoint),
    ]),
  )
  assert result.code == 0 && string.contains(result.stderr, "HTTP 503")
  use _ <- promise.await(h.stop(capture))
  let capture =
    h.capture(
      200,
      "{\"partialSuccess\":{\"rejectedSpans\":\"1\",\"errorMessage\":\"rejected\"}}",
    )
  use result <- promise.await(
    h.cli(["run", "-c", "42"], [
      #("OTEL_EXPORTER_OTLP_ENDPOINT", capture.endpoint),
    ]),
  )
  assert result.code == 0
    && string.contains(result.stderr, "partially accepted traces: rejected")
  h.stop(capture)
}

pub fn disabled_tracing_prevents_requests_and_local_output_test() {
  let capture = h.capture(200, "{}")
  let path = h.temporary_path()
  use result <- promise.await(
    h.cli(["run", "-c", "perform StandardOut(\"hello\")"], [
      #("OTEL_EXPORTER_OTLP_ENDPOINT", capture.endpoint),
      #("OTEL_SDK_DISABLED", "TRUE"),
      #("EYG_PROFILE_FILE", path),
    ]),
  )
  assert result == h.Result(0, "hello", "")
  assert h.spans(capture) == []
  assert simplifile.is_file(path) != Ok(True)
  h.stop(capture)
}

pub fn long_runs_export_bounded_batches_with_complete_ancestry_test() {
  let capture = h.capture(200, "{}")
  let source = list.repeat("let _ = perform Now({})", 260) |> string.join("\n")
  use result <- promise.await(
    h.cli(["run", "-c", source <> "\n0"], [
      #("OTEL_EXPORTER_OTLP_ENDPOINT", capture.endpoint),
    ]),
  )
  assert result.code == 0
  let batches = ref.get(capture.batches)
  assert list.length(batches) == 3
  assert list.all(batches, fn(batch) { list.length(batch.1) <= 128 })
  let all = h.spans(capture)
  assert list.length(all) == 262
  h.verify_tree(all)
  h.stop(capture)
}

pub fn local_chrome_output_and_output_failures_preserve_results_test() {
  let path = h.temporary_path()
  use result <- promise.await(
    h.cli(["run", "-c", "perform Sleep(1)"], [#("EYG_PROFILE_FILE", path)]),
  )
  assert result.code == 0
  let assert Ok(text) = simplifile.read(path)
  let name = {
    use name <- decode.field("name", decode.string)
    decode.success(name)
  }
  let decoder = {
    use names <- decode.field("traceEvents", decode.list(name))
    decode.success(names)
  }
  let assert Ok(names) = json.parse(text, decoder)
  assert list.contains(names, "eyg.effect.Sleep")
  let assert Ok(_) = simplifile.delete(path)
  use result <- promise.map(
    h.cli(["run", "-c", "perform StandardOut(\"done\")"], [
      #("EYG_PROFILE_FILE", path <> "/missing/trace.json"),
    ]),
  )
  assert result.code == 0 && result.stdout == "done"
  assert string.contains(result.stderr, "profile output failed")
}
