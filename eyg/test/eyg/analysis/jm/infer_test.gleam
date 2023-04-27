import gleam/io
import gleam/map
import gleam/set
import gleam/setx
import eygir/expression as e
import eyg/analysis/typ.{ftv} as t
import eyg/analysis/jm/type_
import eyg/analysis/env
import eyg/analysis/inference.{infer, type_of}
// top level analysis
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/unification
import gleeunit/should
import eyg/incremental/store
import eyg/analysis/jm/incremental as jm
import eyg/analysis/jm/type_ as jmt
import eyg/analysis/jm/error as jm_error

fn call2(f, a, b) {
  e.Apply(e.Apply(f, a), b)
}

pub fn example_test() {
  let exp =
    e.Let(
      "equal",
      e.Builtin("equal"),
      e.Let(
        "_",
        call2(e.Variable("equal"), e.Binary(""), e.Binary("")),
        e.Let(
          "_",
          call2(e.Variable("equal"), e.Integer(1), e.Integer(1)),
          e.Empty,
        ),
      ),
    )

  let #(root, store) = store.load(store.empty(), exp)

  let sub = map.new()
  let next = 0
  let env = map.new()
  let source = store.source
  let ref = root
  let types = map.new()

  io.debug("loaded")
  let #(sub, _next, types) =
    jm.infer(sub, next, env, source, ref, jmt.Var(-1), jmt.Var(-2), types)
  map.get(types, root)
  // |> io.debug
  // io.debug(types |> map.to_list)
}
// TODO try and have test for recursive types in rows/effects
