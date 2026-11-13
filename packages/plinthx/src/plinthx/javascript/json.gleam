//// Native JSON serialization for dynamically typed host data.

import gleam/dynamic.{type Dynamic}

@external(javascript, "./json_ffi.mjs", "stringify")
pub fn stringify(value: Dynamic) -> Result(String, String)
