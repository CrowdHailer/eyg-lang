import eyg/cli/tracing_helpers as h
import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import javascript/mutable_reference as ref
import otel/clock
import otel/span
import simplifile

fn profile(code, verify) {
  let capture = h.capture(200, "{}")
  use result <- promise.await(
    h.cli(["profile", "-c", code], [
      #("OTEL_EXPORTER_OTLP_ENDPOINT", capture.endpoint),
    ]),
  )
  let all = h.spans(capture)
  h.verify_tree(all)
  verify(result, all, capture)
  h.stop(capture)
}

fn count(all: List(span.Span), name: String) {
  list.filter(all, fn(s) { s.name == name }) |> list.length
}

fn integer(s: span.Span, name) {
  let assert Ok(span.Integer(n)) = list.key_find(s.attributes, name)
  n
}

pub fn aliases_partial_application_and_callbacks_keep_definition_names_test() {
  profile(
    "let foo = (a, b) -> { !int_add(a, b) }
let alias = foo
let apply = (f, a) -> { f(a) }
let partial = apply(alias, 2)
perform StandardOut(!int_to_string(partial(3)))",
    fn(result, all, _) {
      assert result == h.Result(0, "5", "")
      assert count(all, "foo") == 2 && count(all, "apply") == 2
      assert count(all, "!int_add") > 0
      assert count(all, "alias") == 0 && count(all, "partial") == 0
    },
  )
}

pub fn effect_time_is_counted_once_inside_enclosing_functions_test() {
  profile(
    "let slow = (_) -> { perform Sleep(40) }
let outer = (_) -> { slow({}) }
outer({})",
    fn(result, all, _) {
      assert result.code == 0
      let slow = h.find(all, "slow")
      let outer = h.find(all, "outer")
      let sleep = h.find(all, "eyg.effect.Sleep")
      assert slow.parent_id == Some(outer.span_id)
      let waited = integer(slow, "eyg.profile.effect_ns")
      assert waited >= 35_000_000
      assert waited == integer(sleep, "eyg.profile.effect_ns")
      assert waited == integer(outer, "eyg.profile.effect_ns")
      assert integer(slow, "eyg.profile.self_ns")
        < clock.difference(slow.ended, slow.started)
    },
  )
}

pub fn recursive_frames_and_builtin_callbacks_flush_after_measurement_test() {
  profile(
    "let add = (item, acc) -> { !int_add(item, acc) }
let count = !fix((self, n) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { !list_fold([1, 2, 3], 0, add) }
    | (_) -> { self(!int_subtract(n, 1)) }
  }
})
perform StandardOut(!int_to_string(count(30)))",
    fn(result, all, capture) {
      assert result == h.Result(0, "6", "")
      assert count(all, "add") == 6
      assert count(all, "count") >= 31
      let batches = ref.get(capture.batches) |> list.reverse
      assert list.length(batches) > 1
      let assert [#(received, _), ..] = batches
      assert clock.difference(received, h.find(all, "eyg.run").ended) >= 0
    },
  )
}

pub fn multishot_continuations_preserve_values_and_mark_resumed_frames_test() {
  let code =
    "let double = (x) -> { !int_multiply(x, 2) }
let task = (_) -> { double(perform Choose(10)) }
let handler = (value, resume) -> { !int_add(resume(value), resume(!int_add(value, 1))) }
let result = handle Choose(handler, task)
perform StandardOut(!int_to_string(result))"
  use normal <- promise.await(h.cli(["run", "-c", code], []))
  profile(code, fn(result, all, _) {
    assert result == h.Result(0, "42", "") && normal.stdout == result.stdout
    assert list.any(all, fn(s) {
      list.key_find(s.attributes, "eyg.profile.resumed")
      == Ok(span.Text("true"))
    })
  })
}

pub fn function_errors_and_early_exit_flush_without_changing_status_test() {
  use _ <- promise.await(
    profile(
      "let fail = (_) -> { perform Abort(\"profile failure\") } fail({})",
      fn(result, all, _) {
        assert result.code == 1
        assert h.find(all, "fail").error != None
        assert h.find(all, "eyg.profile").error != None
      },
    ),
  )
  profile("let fail = (_) -> { perform Exit(7) } fail({})", fn(result, all, _) {
    assert result.code == 7
    assert h.find(all, "fail").error != None
    assert h.find(all, "eyg.profile").error != None
  })
}

pub fn chrome_profile_records_named_functions_without_a_collector_test() {
  let path = h.temporary_path()
  use result <- promise.map(
    h.cli(
      ["profile", "-c", "let foo = (a, b) -> { !int_add(a, b) } foo(1, 2)"],
      [#("EYG_PROFILE_FILE", path)],
    ),
  )
  assert result.code == 0 && result.stderr == ""
  let assert Ok(text) = simplifile.read(path)
  let event = {
    use name <- decode.field("name", decode.string)
    use phase <- decode.field("ph", decode.string)
    decode.success(#(name, phase))
  }
  let decoder = {
    use events <- decode.field("traceEvents", decode.list(event))
    decode.success(events)
  }
  let assert Ok(events) = json.parse(text, decoder)
  assert list.length(list.filter(events, fn(e) { e == #("foo", "X") })) == 2
  let assert Ok(_) = simplifile.delete(path)
}

pub fn module_initializers_are_profiled_and_import_purity_is_preserved_test() {
  let path = h.temporary_path()
  let assert Ok(_) =
    simplifile.write(
      path,
      "let initialize = (x) -> { !int_add(x, 1) } let initial = initialize(2) let get = (_) -> { initial } {get}",
    )
  let code =
    "let module = import \""
    <> path
    <> "\" perform StandardOut(!int_to_string(module.get({})))"
  use _ <- promise.await(
    profile(code, fn(result, all, _) {
      assert result == h.Result(0, "3", "")
      assert count(all, "initialize") > 0 && count(all, "get") > 0
    }),
  )
  let assert Ok(_) =
    simplifile.write(path, "perform StandardOut(\"must not execute\")")
  use result <- promise.map(h.cli(["profile", "-c", code], []))
  assert result.code == 1 && result.stdout == ""
  assert string.contains(result.stderr, "effect")
  let assert Ok(_) = simplifile.delete(path)
}
