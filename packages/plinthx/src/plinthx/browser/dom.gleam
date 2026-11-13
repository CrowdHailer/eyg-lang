//// DOM: https://dom.spec.whatwg.org/

pub type Document

pub type Element

pub type Event

@external(javascript, "./dom_ffi.mjs", "getDocument")
pub fn get_document() -> Result(Document, Nil)

@external(javascript, "./dom_ffi.mjs", "getElementById")
pub fn get_element_by_id(document: Document, id: String) -> Result(Element, Nil)

@external(javascript, "./dom_ffi.mjs", "textContent")
pub fn text_content(element: Element) -> Result(String, Nil)

@external(javascript, "./dom_ffi.mjs", "getAttribute")
pub fn get_attribute(element: Element, name: String) -> Result(String, Nil)

@external(javascript, "./dom_ffi.mjs", "setAttribute")
pub fn set_attribute(
  element: Element,
  name: String,
  value: String,
) -> Result(Nil, String)

@external(javascript, "./dom_ffi.mjs", "closest")
pub fn closest(element: Element, selector: String) -> Result(Element, String)

@external(javascript, "./dom_ffi.mjs", "addEventListener")
pub fn add_event_listener(
  element: Element,
  name: String,
  listener: fn(Event) -> Nil,
) -> Result(Nil, String)

/// Narrow a native event target to Element; other EventTargets are absent here.
@external(javascript, "./dom_ffi.mjs", "elementTarget")
pub fn element_target(event: Event) -> Result(Element, Nil)
