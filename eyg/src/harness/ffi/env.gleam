import gleam/map
import gleam/set
import eyg/analysis/typ as t
import eyg/analysis/scheme.{Scheme}
import eyg/runtime/interpreter as r

// harness is definition platforms use it

pub fn empty() {
  r.Env([], map.new())
}
