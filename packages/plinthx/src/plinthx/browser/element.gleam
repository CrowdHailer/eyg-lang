//// HTMLElement and Element methods absent from published Plinth.

import plinth/browser/element.{type Element}
import plinth/browser/window_proxy.{type WindowProxy}

@external(javascript, "./element_ffi.mjs", "click")
pub fn click(element: Element) -> Nil

@external(javascript, "./element_ffi.mjs", "scrollNearest")
pub fn scroll_nearest(element: Element) -> Nil

@external(javascript, "./element_ffi.mjs", "contentWindow")
pub fn content_window(element: Element) -> Result(WindowProxy, Nil)
