import gleam/int
import lustre/element.{button, div, p, text}
import lustre/event.{dispatch, on_click}
import lustre/attribute.{class}
import morph/action

pub fn render(state) {
  div(
    [class("vstack bg-green-500")],
    [
      button([on_click(dispatch(action.Decr))], [text("-")]),
      p([], [text(int.to_string(state))]),
      button([on_click(dispatch(action.Incr))], [text("+")]),
    ],
  )
}
