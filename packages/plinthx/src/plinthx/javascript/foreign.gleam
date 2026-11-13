//// Native ECMAScript functions, arrays and objects at a Dynamic boundary.

import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}

/// Pass a native runtime value through without serialization.
@external(javascript, "./foreign_ffi.mjs", "identity")
pub fn to_dynamic(value: a) -> Dynamic

@external(javascript, "./foreign_ffi.mjs", "apply")
pub fn apply(function: Dynamic, arguments: Array(Dynamic)) -> Dynamic

@external(javascript, "./foreign_ffi.mjs", "isFunction")
pub fn is_function(value: Dynamic) -> Bool

/// Attach a body while delegating invocation to a host callback.
@external(javascript, "./foreign_ffi.mjs", "wrap")
pub fn wrap(body: Dynamic, invoke: fn(Dynamic, Dynamic) -> Dynamic) -> Dynamic

@external(javascript, "./foreign_ffi.mjs", "body")
pub fn body(function: Dynamic) -> Dynamic

@external(javascript, "./foreign_ffi.mjs", "hasBody")
pub fn has_body(function: Dynamic) -> Bool

@external(javascript, "./foreign_ffi.mjs", "length")
pub fn length(value: Dynamic) -> Int

@external(javascript, "./foreign_ffi.mjs", "index")
pub fn index(value: Dynamic, index: Int) -> Dynamic

@external(javascript, "./foreign_ffi.mjs", "object")
pub fn object(entries: Array(#(String, Dynamic))) -> Dynamic

@external(javascript, "./foreign_ffi.mjs", "raise")
pub fn raise(value: Dynamic) -> a
