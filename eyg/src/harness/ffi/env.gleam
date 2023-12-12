import gleam/dict
import eyg/runtime/interpreter as r

pub fn empty() {
  r.Env([], dict.new())
}
