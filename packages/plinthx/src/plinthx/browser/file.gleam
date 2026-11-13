//// File functions that published plinth does not have.

import gleam/dynamic.{type Dynamic}
import plinth/browser/file.{type File}

/// Check that a value is a native File from this browser context.
@external(javascript, "./file_ffi.mjs", "fromDynamic")
pub fn from_dynamic(raw: Dynamic) -> Result(File, Nil)
