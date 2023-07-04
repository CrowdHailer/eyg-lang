import eyg/runtime/interpreter as r
import harness/env.{extend, init}
import harness/ffi/core
import harness/ffi/integer
import harness/ffi/linked_list
import harness/ffi/string

pub fn lib() {
  init()
  |> extend("equal", core.equal())
  |> extend("debug", core.debug())
  |> extend("fix", core.fix())
  |> extend("eval", core.eval())
  |> extend("fixed", core.fixed())
  |> extend("serialize", core.serialize())
  |> extend("capture", core.capture())
  |> extend("encode_uri", core.encode_uri())
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
  |> extend("string_replace", string.replace())
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
