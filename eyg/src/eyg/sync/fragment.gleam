import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state as istate
import eyg/runtime/value as v
import eygir/annotated as a
import gleam/dict
import gleam/dynamic
import gleam/dynamicx
import gleam/list
import harness/stdlib

pub type Scope =
  List(#(String, String))

type Path =
  List(Int)

pub type Value =
  v.Value(Path, #(List(#(istate.Kontinue(Path), Path)), istate.Env(Path)))

pub fn infer(contained, types) {
  let meta = a.get_annotation(contained)

  let #(bindings, _, _, typed) =
    contained
    |> j.do_infer([], isomorphic.Empty, types, 0, j.new_state())

  let #(_, type_info) = typed
  let #(_res, typevar, _eff, _env) = type_info
  let top_type = binding.gen(typevar, -1, bindings)

  let info = a.get_annotation(typed)
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

pub fn eval(contained, values) {
  let env = empty_env(values)
  let handlers = dict.new()
  r.execute(contained, env, handlers)
}

pub fn empty_env(references) -> istate.Env(_) {
  istate.Env(
    ..stdlib.env()
    |> dynamic.from()
    |> dynamicx.unsafe_coerce(),
    references: references,
  )
}
