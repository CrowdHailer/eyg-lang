import gleam/map
import gleam/set
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eyg/analysis/scheme.{Scheme}

pub fn init() {
  #(map.new(), map.new())
}

pub fn extend(state, name, parts) {
  let #(types, implementations) = state
  let #(type_, implementation) = parts

  let scheme = Scheme(set.to_list(t.ftv(type_)), type_)
  let types = map.insert(types, name, scheme)
  let values = map.insert(implementations, name, implementation)
  #(types, values)
}
