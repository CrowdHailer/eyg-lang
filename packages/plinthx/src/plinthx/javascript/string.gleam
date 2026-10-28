//// ECMAScript String: https://tc39.es/ecma262/#sec-string-constructor

import gleam/dynamic.{type Dynamic}

@external(javascript, "./string_ffi.mjs", "from")
pub fn from(value: Dynamic) -> Result(String, String)
