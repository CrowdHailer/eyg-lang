import eyg/analysis/scheme.{Scheme}
import eyg/analysis/typ as t
import gleam/dict
import gleam/set

pub fn init() {
  #(dict.new(), dict.new())
}

pub fn extend(state, name, parts) {
  let #(types, implementations) = state
  let #(type_, implementation) = parts

  let scheme = Scheme(set.to_list(t.ftv(type_)), type_)
  let types = dict.insert(types, name, scheme)
  let values = dict.insert(implementations, name, implementation)
  #(types, values)
}
