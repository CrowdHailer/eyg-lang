//// Run after tracing/cloud_product_check to check the browser-generated programs
//// against the actual cloud harness, including every native trigger input type.

import cloud/beam/execute
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/parser
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import simplifile
import touch_grass/interface

pub fn main() {
  let context =
    infer.pure() |> infer.with_effects(interface.types(execute.harness()))
  list.each([1, 2, 3, 4, 5, 6, 7], fn(index) {
    let file =
      "../tracing/.recordings/quick-trigger-" <> int.to_string(index) <> ".eyg"
    let assert Ok(code) = simplifile.read(file)
    let assert Ok(source) = parser.all_from_string(code)
    let assert infer.Done(analysis) = infer.check(context, source)
    let errors = infer.all_errors(analysis)
    let details =
      list.map(errors, fn(error) { debug.render_reason(error.1) })
      |> string.join("\n")
    assert errors == [] as { file <> ": " <> details }
  })
  io.println(
    "PASS quick triggers: seven programs match the cloud effect and event types",
  )
}
