//// AI SDK and OpenCode plugin library bindings. Routing remains Gleam.

import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}

@external(javascript, "./sdk_ffi.mjs", "schema")
pub fn schema(input: Dynamic) -> Promise(Dynamic)

@external(javascript, "./sdk_ffi.mjs", "jsonSchema")
pub fn json_schema(input: Dynamic) -> Dynamic

@external(javascript, "./sdk_ffi.mjs", "tool")
pub fn tool(input: Dynamic) -> Dynamic

@external(javascript, "./sdk_ffi.mjs", "stringSchema")
pub fn string_schema() -> Dynamic

@external(javascript, "./sdk_ffi.mjs", "createOpencodeClient")
pub fn create_client(options: Dynamic) -> Dynamic
