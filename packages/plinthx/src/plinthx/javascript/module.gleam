//// ECMAScript module metadata. The URL is this binding's own module URL,
//// not the caller's. Callers can resolve other generated package paths from it.

import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}

@external(javascript, "./module_ffi.mjs", "url")
pub fn url() -> String

/// Native dynamic import. Relative specifiers resolve from this binding's URL.
@external(javascript, "./module_ffi.mjs", "load")
pub fn load(specifier: String) -> Promise(Result(Dynamic, String))
