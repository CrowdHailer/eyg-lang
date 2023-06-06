import gleam/dynamic.{Dynamic}
import gleam/option.{Option}
import gleam/javascript/array.{Array}

pub external type Document

pub external type Element

// -------- Search --------
external fn do_query_selector(String) -> Dynamic =
  "" "document.querySelector"

pub fn query_selector(selector) -> Result(Option(Element), _) {
  dynamic.optional(fn(e) { Ok(dynamic.unsafe_coerce(e)) })(do_query_selector(
    selector,
  ))
}

pub external fn query_selector_all(String) -> Array(Element) =
  "../../plinth_ffi.js" "querySelectorAll"

// -------- Elements -------- 

pub external fn create_element(String) -> Element =
  "" "document.createElement"

pub external fn append(Element, Element) -> Nil =
  "../../plinth_ffi.js" "append"

// -------- Other --------
pub external fn insert_after(Element, String) -> Nil =
  "../../plinth_ffi.js" "insertAfter"

external fn do_get(any, String) -> Dynamic =
  "" "Reflect.get"

pub fn inner_text(el: Element) -> String {
  let assert Ok(text) = dynamic.string(do_get(el, "innerText"))
  text
}

external fn do_set(any, String, Dynamic) -> Nil =
  "" "Reflect.set"

pub fn set_text(el: Element, value: String) {
  do_set(el, "innerText", dynamic.from(value))
}

pub fn set_html(el: Element, value: String) {
  do_set(el, "innerHTML", dynamic.from(value))
}

pub external fn on_click(fn(String) -> Nil) -> Nil =
  "../../plinth_ffi.js" "onClick"

pub external fn on_keydown(fn(String) -> Nil) -> Nil =
  "../../plinth_ffi.js" "onKeyDown"
