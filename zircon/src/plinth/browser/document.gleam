import gleam/javascript/array.{Array}
import plinth/browser/element.{Element}

@external(javascript, "../../document_ffi.mjs", "querySelector")
pub fn query_selector(selector: String) -> Result(Element, Nil)

@external(javascript, "../../document_ffi.mjs", "querySelectorAll")
pub fn query_selector_all(a: String) -> Array(Element)
