//// Only bindings to the nginx request object; conversion and effects live in Gleam.

import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}
import gleam/javascript/promise.{type Promise}

pub type Request =
  Dynamic

@external(javascript, "./request_ffi.mjs", "method")
pub fn method(request: Request) -> String

@external(javascript, "./request_ffi.mjs", "path")
pub fn path(request: Request) -> String

@external(javascript, "./request_ffi.mjs", "headers")
pub fn headers(request: Request) -> Array(String)

@external(javascript, "./request_ffi.mjs", "log")
pub fn log(request: Request, message: String) -> Nil

@external(javascript, "./request_ffi.mjs", "subrequest")
pub fn subrequest(request: Request, path: String) -> Promise(Dynamic)

@external(javascript, "./request_ffi.mjs", "finish")
pub fn finish(request: Request, status: Int, body: String) -> Nil
