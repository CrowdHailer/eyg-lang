import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/compile/ir
import eyg/compile/js
import eyg/ir/tree

pub fn to_js(program, refs) {
  program
  |> infer_effects(refs)
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> monadic()
  |> tree.clear_annotation()
  |> js.render()
}

fn infer_effects(program, refs) {
  let #(exp, bindings) =
    program
    |> j.infer(t.Empty, refs, 0, j.new_state())

  tree.map_annotation(exp, fn(types) {
    let #(_, _, effect, _) = types
    binding.resolve(effect, bindings)
  })
}

fn monadic(node: tree.Node(t.Type(Int))) -> tree.Node(t.Type(Int)) {
  let #(exp, meta) = node
  case exp {
    tree.Let(x, #(value, eff), then) ->
      case eff {
        t.Empty -> #(
          tree.Let(x, monadic(#(value, t.Empty)), monadic(then)),
          meta,
        )
        _ -> #(
          tree.Apply(
            #(
              tree.Apply(
                #(tree.Builtin("bind"), t.Empty),
                monadic(#(value, eff)),
              ),
              t.Empty,
            ),
            #(tree.Lambda(x, monadic(then)), t.Empty),
          ),
          t.Empty,
        )
      }
    tree.Apply(func, arg) -> #(tree.Apply(monadic(func), monadic(arg)), meta)
    tree.Lambda(x, body) -> #(tree.Lambda(x, monadic(body)), meta)
    _ -> #(exp, meta)
  }
}
