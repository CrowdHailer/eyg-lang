//// The trusted wrapper forwards requests only from its parent application.

import gleam/list
import gleam/result
import plinthx/browser/node as dom

pub fn main() {
  dom.on_message(fn(message) {
    case dom.from_parent(message) {
      True -> {
        let frame =
          dom.query(dom.document(), "iframe")
          |> result.try(fn(nodes) {
            list.first(nodes) |> result.replace_error("No matching element")
          })
        case frame {
          Ok(frame) -> dom.post_to_frame(frame, dom.message_data(message))
          Error(_) -> Nil
        }
      }
      False -> Nil
    }
  })
}
