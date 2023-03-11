import gleam/map
import gleam/set
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/core
import harness/ffi/integer
import harness/ffi/linked_list
import harness/ffi/string
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

pub fn lib() {
  init()
  |> extend("equal", core.equal())
  |> extend("debug", core.debug())
  |> extend("fix", core.fix())
  |> extend("fixed", core.fixed())
  |> extend("serialize", core.serialize())
  |> extend("promise_await", core.promise_await())
  // integer
  |> extend("int_add", integer.add())
  |> extend("int_subtract", integer.subtract())
  |> extend("int_multiply", integer.multiply())
  |> extend("int_divide", integer.divide())
  |> extend("int_absolute", integer.absolute())
  |> extend("int_parse", integer.parse())
  |> extend("int_to_string", integer.to_string())
  // string
  |> extend("string_append", string.append())
  |> extend("string_uppercase", string.uppercase())
  |> extend("string_lowercase", string.lowercase())
  |> extend("string_length", string.length())
  // list
  |> extend("list_pop", linked_list.pop())
  |> extend("list_fold", linked_list.fold())
}

pub fn env() {
  r.Env([], lib().1)
}
