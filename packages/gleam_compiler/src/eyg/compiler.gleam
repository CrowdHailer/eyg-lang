import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/compiler/ir
import eyg/compiler/js
import eyg/ir/tree
import gleam/dict
import gleam/list
import multiformats/cid/v1

pub fn to_js(
  program: tree.Node(a),
  refs: dict.Dict(v1.Cid, binding.Poly),
  handler: String,
) -> String {
  case js.needs_effect_runtime(program) {
    True -> program |> ir.alpha |> tree.clear_annotation |> js.render(handler)
    False ->
      program
      |> infer_purity(refs)
      |> ir.alpha
      |> ir.k()
      |> ir.unnest
      |> monadic()
      |> tree.clear_annotation()
      |> js.render(handler)
  }
}

/// Compile a checked, closed program to an ES module with deferred host effects.
/// The default export contains program, run, runAsync and the Eff constructor.
/// Inline references before compiling; refs supplies inference types, not code.
pub fn to_module(program, refs) {
  let analysis = j.check_with_references(j.unpure(), refs, program)
  case j.all_errors(analysis) {
    [] ->
      case tree.list_references(program) {
        [] ->
          program |> ir.alpha |> tree.clear_annotation |> js.render_module |> Ok
        references ->
          Error(
            list.map(references, fn(reference) {
              #(program.1, error.MissingReference(reference))
            }),
          )
      }
    errors -> Error(errors)
  }
}

fn infer_purity(program, refs) {
  let j.Analysis(bindings:, tree: exp, ..) =
    j.check_with_references(j.unpure(), refs, program)

  tree.map_annotation(exp, fn(types) {
    let #(checked, _, effect, _) = types
    // Failed inference is not evidence of purity. Preserve sequencing so
    // evaluation still works for programs with type errors.
    checked == Ok(Nil) && binding.resolve(effect, bindings) == t.Empty
  })
}

fn monadic(node: tree.Node(Bool)) -> tree.Node(Bool) {
  let #(exp, meta) = node
  case exp {
    tree.Let(x, #(value, pure), then) ->
      case pure {
        True -> #(tree.Let(x, monadic(#(value, True)), monadic(then)), meta)
        False -> #(
          tree.Apply(
            #(
              tree.Apply(
                #(tree.Builtin("bind"), True),
                monadic(#(value, False)),
              ),
              True,
            ),
            #(tree.Lambda(x, monadic(then)), True),
          ),
          True,
        )
      }
    tree.Apply(func, arg) -> #(tree.Apply(monadic(func), monadic(arg)), meta)
    tree.Lambda(x, body) -> #(tree.Lambda(x, monadic(body)), meta)
    _ -> #(exp, meta)
  }
}
