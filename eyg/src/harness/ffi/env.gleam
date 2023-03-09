import gleam/map
import gleam/set
import eyg/analysis/typ as t
import eyg/analysis/scheme.{Scheme}
import eyg/runtime/interpreter as r

// harness is definition platforms use it
pub fn init() {
  #(map.new(), [])
}

pub fn extend(state, name, parts) {
  let #(types, values) = state
  let #(typ, value) = parts

  let scheme = Scheme(set.to_list(t.ftv(typ)), typ)
  let types = map.insert(types, name, scheme)
  let values = [#(name, value), ..values]
  #(types, values)
}

pub fn empty() {
  r.Env([], map.new())
}
