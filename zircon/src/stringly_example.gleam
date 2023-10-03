import plinth/browser/document
import plinth/browser/element
import stringly as h

fn page(x) {
  h.div(
    [],
    [
      h.button([h.onclick(fn(x) { x + 1 })], [h.text("up")]),
      h.button([h.onclick(fn(x) { x - 1 })], [h.text("down")]),
    ],
  )([])
//   can have a h.container that serialises code
// recursivly put in page render with map of code
}

pub fn run() {
  let assert Ok(body) = document.query_selector("body")
  let #(content, listeners) = page(0)
  element.set_inner_html(body, content)
  // inner html
  todo
}
