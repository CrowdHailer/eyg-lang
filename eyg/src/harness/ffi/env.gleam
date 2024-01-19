import gleam/dict
import eyg/runtime/interpreter/state

pub fn empty() {
  state.Env([], dict.new())
}
