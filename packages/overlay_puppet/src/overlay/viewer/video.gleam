//// Native media controls plus speed selection and a visible decoding failure.

import gleam/float
import gleam/int
import gleam/result
import plinthx/browser/node as dom

pub fn main() {
  let assert Ok(video) = dom.by_id("video")
  let assert Ok(speed) = dom.by_id("speed")
  dom.listen(speed, "change", fn(event) {
    case dom.value(dom.target(event)) {
      Ok(value) ->
        case
          int.parse(value)
          |> result.map(int.to_float)
          |> result.or(float.parse(value))
        {
          Ok(value) -> dom.set_number(video, "playbackRate", value)
          Error(_) -> Nil
        }
      Error(_) -> Nil
    }
  })
  dom.listen(video, "error", fn(_) {
    let assert Ok(status) = dom.by_id("status")
    dom.set_text(
      status,
      "textContent",
      "This browser could not decode the supplied video.",
    )
  })
}
