import eyg/runtime/interpreter as r
import harness/ffi/core

pub fn lib() {
  core.lib()
  // part of core/lib
  // |> extend("eval", core.eval())
}

pub fn env() {
  r.Env([], lib().1)
}
