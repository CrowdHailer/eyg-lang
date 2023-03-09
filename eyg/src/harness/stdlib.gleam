import harness/ffi/env
import harness/ffi/core
import harness/ffi/integer
import harness/ffi/linked_list
import harness/ffi/string

pub fn lib() {
  env.init()
  // |> env.extend("equal", core.equal())
  |> env.extend("debug", core.debug())
  |> env.extend("fix", core.fix())
  |> env.extend("serialize", core.serialize())
  // integer
  |> env.extend("ffi_add", integer.add())
  |> env.extend("ffi_subtract", integer.subtract())
  |> env.extend("ffi_multiply", integer.multiply())
  |> env.extend("ffi_divide", integer.divide())
  |> env.extend("ffi_absolute", integer.absolute())
  |> env.extend("ffi_int_parse", integer.int_parse())
  |> env.extend("ffi_int_to_string", integer.int_to_string())
  // string
  |> env.extend("ffi_append", string.append())
  |> env.extend("ffi_uppercase", string.uppercase())
  |> env.extend("ffi_lowercase", string.lowercase())
  |> env.extend("ffi_length", string.length())
  // list
  |> env.extend("ffi_fold", linked_list.fold())
  |> env.extend("ffi_pop", linked_list.pop())
}
