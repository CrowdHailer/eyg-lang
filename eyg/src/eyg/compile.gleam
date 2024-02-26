import eyg/analysis/type_/isomorphic as t
import eyg/analysis/inference/levels_j/contextual as j
import eygir/annotated as a
import eyg/analysis/type_/binding
import eyg/compile/ir
import eyg/compile/js

pub fn to_js(program) {
  program
  |> infer_effects()
  |> ir.alpha
  |> ir.k()
  |> ir.unnest
  |> monadic()
  |> a.drop_annotation()
  |> js.render()
}

fn infer_effects(program) {
  let #(exp, bindings) =
    program
    |> a.drop_annotation()
    |> j.infer(t.Empty, 0, j.new_state())

  a.map_annotation(exp, fn(types) {
    let #(_, _, effect, _) = types
    binding.resolve(effect, bindings)
  })
}

fn monadic(node) {
  let #(exp, meta) = node
  case exp {
    a.Let(x, #(value, eff), then) ->
      case eff {
        t.Empty -> #(a.Let(x, #(value, t.Empty), monadic(then)), meta)
        _ -> #(
          a.Apply(
            #(a.Apply(#(a.Builtin("bind"), t.Empty), #(value, eff)), t.Empty),
            #(a.Lambda(x, monadic(then)), t.Empty),
          ),
          t.Empty,
        )
      }
    _ -> #(exp, meta)
  }
}
