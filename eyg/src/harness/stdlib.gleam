import gleam/io
import gleam/map
import eyg/runtime/interpreter as r
import harness/ffi/env
import harness/ffi/core
import harness/ffi/integer
import harness/ffi/linked_list
import harness/ffi/string

pub fn lib() {
  #(map.new(), env())
}

pub fn env() {
  r.Env(
    [],
    map.new()
    |> map.insert("equal", core.equal())
    |> map.insert("debug", core.debug())
    |> map.insert("fix", core.fix())
    |> map.insert("serialize", core.serialize())
    // integer
    |> map.insert("int_add", integer.add())
    |> map.insert("int_subtract", integer.subtract())
    |> map.insert("int_multiply", integer.multiply())
    |> map.insert("int_divide", integer.divide())
    |> map.insert("int_absolute", integer.absolute())
    |> map.insert("int_parse", integer.parse())
    |> map.insert("int_to_string", integer.to_string())
    // string
    |> map.insert("string_append", string.append())
    |> map.insert("string_uppercase", string.uppercase())
    |> map.insert("string_lowercase", string.lowercase())
    |> map.insert("string_length", string.length())
    // list
    |> map.insert("list_pop", linked_list.pop())
    |> map.insert("list_fold", linked_list.fold()),
  )
}
