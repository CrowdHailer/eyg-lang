//// Bindings to the pi-agent-core and TypeBox libraries only.

import gleam/dynamic.{type Dynamic}

@external(javascript, "./sdk_ffi.mjs", "agent")
pub fn agent(options: Dynamic) -> Dynamic

@external(javascript, "./sdk_ffi.mjs", "objectSchema")
pub fn object_schema(properties: Dynamic) -> Dynamic

@external(javascript, "./sdk_ffi.mjs", "stringSchema")
pub fn string_schema(options: Dynamic) -> Dynamic
