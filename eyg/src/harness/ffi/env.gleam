import eyg/runtime/interpreter/state
import gleam/dict

pub fn empty() {
  state.Env([], dict.new(), dict.new())
}
