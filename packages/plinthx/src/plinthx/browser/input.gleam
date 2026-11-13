//// File input events: https://html.spec.whatwg.org/multipage/input.html

import gleam/dynamic.{type Dynamic}
import plinth/browser/file.{type File}

@external(javascript, "./input_ffi.mjs", "eventFile")
pub fn event_file(event: Dynamic) -> Result(File, Nil)
