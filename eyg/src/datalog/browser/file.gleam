import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}
import gleam/javascript/promise.{type Promise}

pub type File

@external(javascript, "../../datalog_ffi.mjs", "files")
pub fn event_files(event: Dynamic) -> Array(File)

@external(javascript, "../../datalog_ffi.mjs", "name")
pub fn name(file: File) -> Array(File)

@external(javascript, "../../datalog_ffi.mjs", "mime")
pub fn mime(file: File) -> Array(File)

// Blob methods

@external(javascript, "../../datalog_ffi.mjs", "text")
pub fn text(file: File) -> Promise(String)
