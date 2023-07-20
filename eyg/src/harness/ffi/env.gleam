import gleam/map
import eyg/runtime/interpreter as r

pub fn empty() {
  r.Env([], map.new())
}
