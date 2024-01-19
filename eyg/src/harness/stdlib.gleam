import eyg/runtime/interpreter/state
import harness/ffi/core

pub fn lib() {
  core.lib()
  // part of core/lib
  // |> extend("eval", core.eval())
}

pub fn env() {
  state.Env([], lib().1)
}
