import eyg/runtime/interpreter as r
import harness/env.{extend}
import harness/ffi/core

pub fn lib() {
  core.lib()
  |> extend("eval", core.eval())
}

pub fn env() {
  r.Env([], lib().1, [])
}
