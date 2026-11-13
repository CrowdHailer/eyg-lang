//// Validate source-derived types without capturing or evaluating runtime values.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import gleam/string

pub fn generalise(type_: binding.Mono) -> binding.Poly {
  let bindings =
    set.fold(infer.ftv(type_), dict.new(), fn(bindings, id) {
      dict.insert(bindings, id, binding.Unbound(1))
    })
  binding.gen(type_, 0, bindings)
}

pub fn analysis(analysis: infer.Analysis(_)) {
  case infer.all_errors(analysis) {
    [] -> Ok(infer.poly_type(analysis))
    errors ->
      Error(
        list.map(errors, fn(error) { debug.render_reason(error.1) })
        |> string.join("\n"),
      )
  }
}

pub fn matches(actual: binding.Poly, expected: binding.Mono) {
  let #(actual, bindings) = binding.instantiate(actual, 1, dict.new())
  let #(expected, bindings) =
    binding.instantiate(generalise(expected), 1, bindings)
  unify.unify_with_bindings(actual, expected, 1, bindings)
  |> result.replace(Nil)
  |> result.map_error(fn(error) { debug.render_reason(error.0) })
}

pub fn fields(type_: binding.Poly) {
  case type_ {
    t.Record(rows) -> Ok(row_fields(rows))
    _ -> Error("Expected a record")
  }
}

fn row_fields(rows) {
  case rows {
    t.RowExtend(name, type_, rest) -> [#(name, type_), ..row_fields(rest)]
    _ -> []
  }
}

pub fn field(type_: binding.Poly, name: String) {
  use fields <- result.try(fields(type_))
  list.key_find(fields, name)
  |> result.replace_error("Missing field " <> name)
}

pub fn call(function: binding.Poly, argument: binding.Mono) {
  let context =
    infer.Context(..infer.pure(), env: [
      #("f", function),
      #("arg", generalise(argument)),
    ])
  let assert infer.Done(checked) =
    infer.check(context, ir.call(ir.variable("f"), [ir.variable("arg")]))
  analysis(checked)
}
