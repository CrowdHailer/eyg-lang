//// The carousel behavior included in the EYG viewer bundle.

import gleam/int
import gleam/list
import gleam/result
import javascript/mutable_reference as ref
import plinthx/browser/node as dom

pub fn main() {
  let figures = dom.query(dom.document(), "figure") |> result.unwrap([])
  let length = list.length(figures)
  let index = ref.new(0)
  let assert Ok(previous) = dom.by_id("previous")
  let assert Ok(next) = dom.by_id("next")
  let render = fn() {
    list.index_map(figures, fn(figure, at) {
      dom.set_flag(figure, "hidden", at != ref.get(index))
    })
    let assert Ok(position) = dom.by_id("position")
    dom.set_text(position, "textContent", case length {
      0 -> "0 / 0"
      _ -> int.to_string(ref.get(index) + 1) <> " / " <> int.to_string(length)
    })
    let assert Ok(empty) = dom.by_id("empty")
    dom.set_flag(empty, "hidden", length > 0)
    dom.set_flag(previous, "disabled", length < 2)
    dom.set_flag(next, "disabled", length < 2)
  }
  let advance = fn(amount) {
    case length > 0 {
      True -> {
        ref.set(index, { ref.get(index) + length + amount } % length)
        render()
      }
      False -> Nil
    }
  }
  dom.listen(previous, "click", fn(_) { advance(-1) })
  dom.listen(next, "click", fn(_) { advance(1) })
  dom.listen(dom.document(), "keydown", fn(event) {
    case dom.key(event) {
      "ArrowRight" -> advance(1)
      "ArrowLeft" -> advance(-1)
      _ -> Nil
    }
  })
  render()
}
