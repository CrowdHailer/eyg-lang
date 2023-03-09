import gleam/io
import gleam/map
import eyg/runtime/interpreter as r
import harness/ffi/env
import harness/ffi/core
import harness/ffi/integer
import harness/ffi/linked_list
import harness/ffi/string

pub fn lib() {
  // env.init()

  // // string
  // |> env.extend("ffi_append", string.append())
  // |> env.extend("ffi_uppercase", string.uppercase())
  // |> env.extend("ffi_lowercase", string.lowercase())
  // |> env.extend("ffi_length", string.length())
  // // list
  // |> env.extend("ffi_fold", linked_list.fold())
  // |> env.extend("ffi_pop", linked_list.pop())
  // todo("pull out here")
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
    // |> map.insert("int_subtract", integer.subtract())
    // |> map.insert("int_multiply", integer.multiply())
    // |> map.insert("int_divide", integer.divide())
    // |> map.insert("int_absolute", integer.absolute())
    // |> map.insert("int_int_parse", integer.int_parse())
    // |> map.insert("int_int_to_string", integer.int_to_string())
    // string
    |> map.insert("string_append", string.append())
    // list
    |> map.insert("list_pop", linked_list.pop())
    |> map.insert("list_fold", linked_list.fold()),
  )
}
