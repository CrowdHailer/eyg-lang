import eyg/compiler
import eyg/compiler/js
import eyg/parser
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/list
import gleam/string
import plinth/browser/window
import plinthx/javascript/foreign
import simplifile

fn compiled(source) {
  let assert Ok(source) = parser.all_from_string(source)
  compiler.to_js(source, dict.new(), js.basic)
}

fn measured(source) {
  let code =
    compiled(source)
    |> string.replace("\n$run(", "\nconst $workload = $run(")
  let assert Ok(value) = window.eval(code <> ";\n[$workload, $runtime.metrics]")
  let assert Ok([workload, metrics]) =
    decode.run(value, decode.list(decode.dynamic))
  #(workload, metrics)
}

fn items(count) {
  let unit = foreign.object(array.from_list([]))
  list.fold(
    list.repeat(unit, count),
    foreign.to_dynamic(array.from_list([])),
    fn(tail, head) { foreign.to_dynamic(array.from_list([head, tail])) },
  )
}

fn sample(workload, metrics, count) {
  let value = foreign.apply(workload, array.from_list([items(count)]))
  let metrics = foreign.apply(metrics, array.from_list([]))
  let assert Ok(depth) =
    decode.run(metrics, decode.field("depth", decode.int, decode.success))
  let assert Ok(captured) =
    decode.run(metrics, decode.field("captured", decode.int, decode.success))
  #(value, depth, captured)
}

fn check(path, expected: fn(Int) -> Dynamic) {
  let assert Ok(source) = simplifile.read(path)
  let #(workload, metrics) = measured(source)
  let #(value, depth, captured) = sample(workload, metrics, 10)
  assert value == expected(10)
  assert depth > 0
  assert captured > 0
  let #(value, large_depth, large_captured) = sample(workload, metrics, 10_000)
  assert value == expected(10_000)
  assert large_depth == depth
  assert large_captured == captured
}

pub fn stateful_handler_has_bounded_stack_and_capture_test() {
  check("../../guides/examples/stateful_handler_workload.eyg", dynamic.int)
}

pub fn shallow_state_has_bounded_stack_and_capture_test() {
  check("../../spec/evaluation/shallow_counter.eyg", dynamic.int)
}

pub fn interleaved_handlers_have_bounded_stack_and_capture_test() {
  check("../../guides/examples/composed_stateful_workload.eyg", fn(n) {
    foreign.object(
      array.from_list([
        #("state", dynamic.int(n)),
        #(
          "value",
          foreign.object(
            array.from_list([
              #("state", dynamic.int(n)),
              #("value", dynamic.int(2 * n)),
            ]),
          ),
        ),
      ]),
    )
  })
}

pub fn fixed_tail_recursion_is_stack_safe_in_compiled_javascript_test() {
  let code =
    compiled(
      "let loop = !fix((self, n) -> { match !int_compare(n, 0) { Eq(_) -> { 42 } | (_) -> { self(!int_subtract(n, 1)) } } }) loop(100000)",
    )
  assert window.eval(code) == Ok(dynamic.int(42))
}

pub fn multiple_resumptions_keep_independent_state_test() {
  let code =
    compiled(
      "handle Choose((_, resume) -> { !int_add(resume(10), resume(20)) }, (_) -> {
    let run = handle Increment((_, resume) -> {
      (state) -> { let next = !int_add(state, 1) resume(next)(next) }
    }, (_) -> {
      let choice = perform Choose({})
      let _ = perform Increment({})
      let finish = (state) -> { !int_add(choice, state) }
      finish
    })
    run(0)
  })",
    )
  assert window.eval(code) == Ok(dynamic.int(32))
}
