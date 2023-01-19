import gleam/io
import gleam/map
import gleam/set
import eyg/analysis/typ as t
import eyg/analysis/scheme.{Scheme}

// harness is definition platforms use it
pub fn init() {
  #(map.new(), [])
}

pub fn extend(state, name, parts) {
  let #(types, values) = state
  let #(typ, value) = parts

  let scheme = Scheme(set.to_list(t.ftv(typ)), typ)
  // TODO can shrink globally
  let types = map.insert(types, name, scheme)
  let values = [#(name, value), ..values]
  #(types, values)
}
