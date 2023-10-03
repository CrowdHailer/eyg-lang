import gleam/io
import gleeunit/should
import stringly as h

fn render(component) {
  let #(string, listeners) = component([])
  string
}

pub fn text_test() {
  render(h.text("hey"))
  |> should.equal("hey")
}

pub fn children_test() {
  render(h.div([], [h.text("hello, "), h.text("world!")]))
  |> should.equal("<div>hello, world!</div>")
}

pub fn click_test() {
  let #(content, listeners) =
    h.div(
      [],
      [
        h.button([h.onclick(fn(x) { x + 1 })], [h.text("up")]),
        h.button([h.onclick(fn(x) { x - 1 })], [h.text("down")]),
      ],
    )([])
  io.debug(listeners)
  content
  |> should.equal("<div>hello, world!</div>")
}
