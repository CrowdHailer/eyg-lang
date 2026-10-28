//// Native ECMAScript functions, arrays and objects at a Dynamic boundary.

import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}
import gleam/javascript/promise.{type Promise}

/// Pass a native runtime value through without serialization.
@external(javascript, "./foreign_ffi.mjs", "identity")
pub fn to_dynamic(value: a) -> Dynamic

@external(javascript, "./foreign_ffi.mjs", "nullValue")
pub fn null_value() -> Dynamic

@external(javascript, "./foreign_ffi.mjs", "apply")
pub fn apply(function: Dynamic, arguments: Array(Dynamic)) -> Dynamic

/// Invoke a native object's method with its receiver preserved.
@external(javascript, "./foreign_ffi.mjs", "call")
pub fn call(
  object: Dynamic,
  method: String,
  arguments: Array(Dynamic),
) -> Dynamic

@external(javascript, "./foreign_ffi.mjs", "tryApply")
pub fn try_apply(
  function: Dynamic,
  arguments: Array(Dynamic),
) -> Result(Dynamic, Dynamic)

@external(javascript, "./foreign_ffi.mjs", "isFunction")
pub fn is_function(value: Dynamic) -> Bool

@external(javascript, "./foreign_ffi.mjs", "isUndefined")
pub fn is_undefined(value: Dynamic) -> Bool

@external(javascript, "./foreign_ffi.mjs", "isUint8Array")
pub fn is_uint8_array(value: Dynamic) -> Bool

@external(javascript, "./foreign_ffi.mjs", "isThenable")
pub fn is_thenable(value: Dynamic) -> Bool

@external(javascript, "./foreign_ffi.mjs", "error")
pub fn error(message: String) -> Dynamic

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

@external(javascript, "./foreign_ffi.mjs", "hasOwn")
pub fn has_own(object: Dynamic, key: String) -> Bool

@external(javascript, "./foreign_ffi.mjs", "property")
pub fn property(object: Dynamic, key: String) -> Dynamic

/// Assimilate a native promise, thenable or immediate host value.
@external(javascript, "./foreign_ffi.mjs", "promise")
pub fn to_promise(value: Dynamic) -> Promise(Dynamic)

@external(javascript, "./foreign_ffi.mjs", "raise")
pub fn raise(value: Dynamic) -> a
