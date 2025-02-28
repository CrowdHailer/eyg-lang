import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic
import eyg/interpreter/state as istate
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/list

pub type Scope =
  List(#(String, String))

type Path =
  List(Int)

pub type Value =
  v.Value(Path, #(List(#(istate.Kontinue(Path), Path)), istate.Env(Path)))

pub fn infer(contained, types) {
  let meta = ir.get_annotation(contained)

  let #(bindings, _, _, typed) =
    contained
    |> j.do_infer([], isomorphic.Empty, types, 0, j.new_state())

  let #(_, type_info) = typed
  let #(_res, typevar, _eff, _env) = type_info
  let top_type = binding.gen(typevar, -1, bindings)

  let info = ir.get_annotation(typed)
  let assert Ok(info) = list.strict_zip(meta, info)
  let new_errors =
    info
    |> list.filter_map(fn(pair) {
      let #(path, #(result, _type, _eff, _scope)) = pair
      case result {
        Ok(Nil) -> Error(Nil)
        Error(reason) -> Ok(#(path, reason))
      }
    })
  #(top_type, new_errors)
}
