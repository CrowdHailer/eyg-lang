import gleam/int
import lustre/element.{button, div, p, pre, text}
import lustre/event.{dispatch, on_click}
import lustre/attribute.{class}
import morph/action
// TODO move to state
import source.{source}
import morph/components/code

pub fn render(state) {
  div(
    [class("h-screen vstack")],
    [
      div([class("spacer")], []),
      div(
        [class("cover")],
        [
          button([on_click(dispatch(action.Decr))], [text("-")]),
          p([], [text(int.to_string(state))]),
          button([on_click(dispatch(action.Incr))], [text("+")]),
        ],
      ),
      // code.render(source),
      pre([], code.render_text(source, "\n")),
      div([class("spacer")], []),
      div([class("cover bg-gray-100")], [text("morph")]),
    ],
  )
}
