import gleam/javascript/array.{type Array}

pub type Document

pub type Element

pub type Event

// -------- Search --------

@external(javascript, "../../plinth_ffi.js", "querySelector")
pub fn query_selector(a: Element, b: String) -> Result(Element, Nil)

@external(javascript, "../../plinth_ffi.js", "doc")
pub fn document() -> Element

@external(javascript, "../../plinth_ffi.js", "querySelectorAll")
pub fn query_selector_all(a: String) -> Array(Element)

@external(javascript, "../../plinth_ffi.js", "closest")
pub fn closest(a: Element, b: String) -> Result(Element, Nil)

@external(javascript, "../../plinth_ffi.js", "nextElementSibling")
pub fn next_element_sibling(a: Element) -> Element

// -------- Elements --------

@external(javascript, "../../plinth_ffi.js", "createElement")
pub fn create_element(a: String) -> Element

@external(javascript, "../../plinth_ffi.js", "setAttribute")
pub fn set_attribute(a: Element, b: String, c: String) -> Nil

@external(javascript, "../../plinth_ffi.js", "append")
pub fn append(a: Element, b: Element) -> Nil

// append works on children, not referenced in block components
@external(javascript, "../../plinth_ffi.js", "insertElementAfter")
pub fn insert_element_after(a: Element, b: Element) -> Nil

@external(javascript, "../../plinth_ffi.js", "remove")
pub fn remove(a: Element) -> Nil

// -------- Elements Attributes --------

@external(javascript, "../../plinth_ffi.js", "datasetGet")
pub fn dataset_get(a: Element, b: String) -> Result(String, Nil)

// -------- Event --------

@external(javascript, "../../plinth_ffi.js", "addEventListener")
pub fn add_event_listener(
  a: Element,
  b: String,
  c: fn(Event) -> Nil,
) -> fn() -> Nil

@external(javascript, "../../plinth_ffi.js", "target")
pub fn target(a: Event) -> Element

@external(javascript, "../../plinth_ffi.js", "eventKey")
pub fn key(a: Event) -> String

// returns the first only
@external(javascript, "../../plinth_ffi.js", "getTargetRange")
pub fn get_target_range(a: Event) -> Nil

@external(javascript, "../../plinth_ffi.js", "preventDefault")
pub fn prevent_default(a: Event) -> Nil

// -------- Other --------

@external(javascript, "../../plinth_ffi.js", "insertAfter")
pub fn insert_after(a: Element, b: String) -> Nil

@external(javascript, "../../plinth_ffi.js", "innerText")
pub fn inner_text(el: Element) -> String

@external(javascript, "../../plinth_ffi.js", "setInnerText")
pub fn set_text(el: Element, value: String) -> Nil

@external(javascript, "../../plinth_ffi.js", "setInnerHTML")
pub fn set_html(el: Element, value: String) -> Nil

// TODO fix proper action or add event listener
@external(javascript, "../../plinth_ffi.js", "onClick")
pub fn on_click(a: fn(String) -> Nil) -> Nil

@external(javascript, "../../plinth_ffi.js", "onKeyDown")
pub fn on_keydown(a: fn(String) -> Nil) -> Nil

@external(javascript, "../../plinth_ffi.js", "onChange")
pub fn on_change(a: fn(String) -> Nil) -> Nil
