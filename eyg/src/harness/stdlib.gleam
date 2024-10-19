import eyg/runtime/interpreter/state
import gleam/dict
import harness/ffi/core

pub fn new_env(scope, references) {
  state.Env(scope: scope, references: references, builtins: core.lib().1)
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
