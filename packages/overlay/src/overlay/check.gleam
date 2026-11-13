//// Type check evaluated values before admitting them as policies or handlers.
//// The host resolves references; this module performs no host effects.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/capture
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

pub fn value(
  value: state.Value(meta),
  expected: binding.Mono,
  meta: meta,
  lookup: fn(ir.Reference) -> Result(state.Value(meta), String),
) -> Result(Nil, String) {
  // Instantiate the interface's type variables independently from inference's
  // fresh variables. with_effect registers every variable in the supplied type.
  let registered = infer.with_effect(infer.pure(), "Expected", expected, t.unit)
  let generic = binding.gen(expected, 0, registered.bindings)
  let #(expected, bindings) = binding.instantiate(generic, 1, dict.new())
  let context = infer.Context(..infer.pure(), bindings:)
  use source <- result.try(source(value, meta))
  use _ <- result.map(
    analyse(
      infer.check(infer.with_expected_type(context, expected), source),
      meta,
      lookup,
      [],
    ),
  )
  Nil
}

fn source(value, meta) {
  case capture.is_capturable(value) {
    True -> Ok(capture.capture(value, meta))
    False -> Error("A continuation cannot be type checked")
  }
}

fn analyse(step, meta, lookup, visiting) {
  case step {
    infer.Done(analysis) ->
      case infer.all_errors(analysis) {
        [] -> Ok(infer.poly_type(analysis))
        errors ->
          Error(
            list.map(errors, fn(error) { debug.render_reason(error.1) })
            |> string.join("\n"),
          )
      }
    infer.Lookup(reference, resume) -> {
      let type_ = case list.contains(visiting, reference) {
        True -> Error("Cyclic reference while checking a value")
        False -> {
          use value <- result.try(lookup(reference))
          use source <- result.try(source(value, meta))
          analyse(infer.check(infer.pure(), source), meta, lookup, [
            reference,
            ..visiting
          ])
        }
      }
      use type_ <- result.try(type_)
      analyse(resume(Ok(type_)), meta, lookup, visiting)
    }
  }
}
