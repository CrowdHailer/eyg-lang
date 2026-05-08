//// The reload component allows no effects

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/state.{type Value}
import eyg/ir/tree as ir
import gleam/list
import gleam/option.{type Option, None, Some}
import morph/analysis
import website/run

// helpers

// Type checking ------------------------------

fn handle_t(state, message) {
  t.Fun(state, t.Empty, t.Fun(message, t.Empty, state))
}

fn render_t(state) {
  t.Fun(state, t.Empty, t.String)
}

pub fn type_check(
  context: run.Context(a),
  source: ir.Node(List(Int)),
  value: Option(Value(Nil)),
) -> #(analysis.Analysis, Bool) {
  let bindings = infer.new_state()
  let #(app_state_t, bindings) = case value {
    Some(v) -> {
      let #(poly, bindings) = analysis.value_to_type(v, bindings, Nil)
      binding.instantiate(poly, 1, bindings)
    }
    None -> binding.mono(1, bindings)
  }
  let types = run.module_types(context)

  do_check_against_state(bindings, types, source, app_state_t)
}

fn do_check_against_state(b, refs, source, old) {
  let level = 1
  let context = analysis.Context(b, [], [], refs, [])
  let #(tree, b) = infer.infer(source, t.Empty, refs, level, b)

  let #(inner, meta) = tree
  let #(original_err, program, _, _) = meta

  let #(rest, b) = binding.mono(level, b)
  let #(new, b) = binding.mono(level, b)

  // Needs to be open for handle etc
  let init_field = t.Record(t.do_rows([#("init", new)], rest))

  let #(meta, b, migrate) = case unify.unify(init_field, program, level, b) {
    Ok(b) -> {
      // if has init check if init is old or new state type
      let #(migrate_field, upgrade, b) = case unify.unify(old, new, level, b) {
        Ok(b) -> #([], False, b)
        Error(_reason) -> {
          let migrate_field = #("migrate", t.Fun(old, t.Empty, new))
          #([migrate_field], True, b)
        }
      }
      let #(new_message, b) = binding.mono(level, b)
      let handle_field = #("handle", handle_t(new, new_message))
      let render_field = #("render", render_t(new))
      let #(remainder, b) = binding.mono(level, b)

      let expect =
        t.do_rows([handle_field, render_field, ..migrate_field], remainder)
      case unify.unify(expect, rest, level, b) {
        Ok(b) -> #(
          #(
            case original_err {
              Ok(_) -> Ok(Nil)
              // keep original error because if it did error then calculation proceeds with permissive type
              Error(reason) -> Error(reason)
            },
            program,
            t.Empty,
            [],
          ),
          b,
          upgrade,
        )
        Error(reason) -> #(#(Error(reason), program, t.Empty, []), b, False)
      }
    }
    Error(reason) -> {
      #(#(Error(reason), program, t.Empty, []), b, False)
    }
  }
  let tree: ir.Node(_) = #(inner, meta)
  let paths = ir.get_annotation(source)
  let info = ir.get_annotation(tree)
  let assert Ok(inferred) = list.strict_zip(paths, info)
  #(analysis.Analysis(bindings: b, inferred: inferred, context:), migrate)
}
