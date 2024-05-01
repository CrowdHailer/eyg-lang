import gleam/io
import plinth/browser/document
import plinth/browser/element
import plinth/browser/window

pub fn update_focus() {
  window.request_animation_frame(fn() {
    case document.query_selector("#focus-input") {
      Ok(el) -> {
        element.focus(el)
      }
      _ -> {
        let assert Ok(el) = document.query_selector("#code")
        element.focus(el)
      }
    }
  })
}

pub fn scroll_to() {
  window.request_animation_frame(fn() {
    case document.query_selector("#highlighted") {
      Ok(el) -> {
        element.scroll_into_view(el)
      }
      _ -> {
        io.debug(document.query_selector_all("#highlighted"))
        io.debug("didn't find element")
        Nil
      }
    }
  })
}
