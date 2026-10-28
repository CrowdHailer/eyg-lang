//// HTML interfaces: https://html.spec.whatwg.org/

import plinthx/browser/dom.{type Element}

pub type Location

@external(javascript, "./html_ffi.mjs", "getLocation")
pub fn get_location() -> Result(Location, Nil)

@external(javascript, "./html_ffi.mjs", "hash")
pub fn hash(location: Location) -> String

@external(javascript, "./html_ffi.mjs", "search")
pub fn search(location: Location) -> String

@external(javascript, "./html_ffi.mjs", "setInnerHtml")
pub fn set_inner_html(element: Element, html: String) -> Result(Nil, String)

@external(javascript, "./html_ffi.mjs", "inputValue")
pub fn input_value(element: Element) -> Result(String, Nil)

@external(javascript, "./html_ffi.mjs", "selectValue")
pub fn select_value(element: Element) -> Result(String, Nil)

@external(javascript, "./html_ffi.mjs", "inputChecked")
pub fn input_checked(element: Element) -> Result(Bool, Nil)

@external(javascript, "./html_ffi.mjs", "setInputValue")
pub fn set_input_value(element: Element, value: String) -> Result(Nil, String)

@external(javascript, "./html_ffi.mjs", "setSelectValue")
pub fn set_select_value(element: Element, value: String) -> Result(Nil, String)
