import eyg/runtime/interpreter/state
import gleam/dict
import harness/ffi/core

pub fn new_env(scope, references) -> state.Env(a) {
  state.Env(scope: scope, references: references, builtins: core.lib().1)
}

pub fn env() {
  state.Env([], dict.new(), core.lib().1)
}
