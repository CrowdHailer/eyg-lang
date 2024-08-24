import eyg/runtime/interpreter/state
import gleam/dict
import harness/ffi/core

pub fn lib() {
  core.lib()
  // part of core/lib
  // |> extend("eval", core.eval())
}

pub fn env() {
  state.Env([], dict.new(), lib().1)
}
