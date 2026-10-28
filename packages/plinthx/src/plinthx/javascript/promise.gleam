//// ECMAScript Promise: https://tc39.es/ecma262/#sec-promise-objects

import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}

pub type Constructor

@external(javascript, "./promise_ffi.mjs", "get")
pub fn get() -> Result(Constructor, Nil)

/// Preserve the native rejected promise and its original rejection value.
@external(javascript, "./promise_ffi.mjs", "reject")
pub fn reject(constructor: Constructor, reason: Dynamic) -> Promise(a)
