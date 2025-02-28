import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/dynamicx
import harness/ffi/core

pub type Value(meta) =
  v.Value(meta, #(List(#(state.Kontinue(meta), meta)), state.Env(meta)))

pub fn new_env(
  scope: List(#(String, Value(a))),
  references: Dict(String, Value(a)),
) {
  let builtins =
    core.lib().1
    |> dynamic.from
    |> dynamicx.unsafe_coerce
  state.Env(scope: scope, references: references, builtins: builtins)
}

pub fn lib() {
  core.lib()
  // part of core/lib
  // |> extend("eval", core.eval())
}

pub fn env() {
  state.Env([], dict.new(), lib().1)
}

pub fn env_and_ref(refs) {
  state.Env([], refs, lib().1)
}
