import gleam/option.{Some}
import lustre/element.{button, div, p, pre, text}
import lustre/event.{dispatch, on_click}
import lustre/attribute.{class}
import morph/action
// TODO move to state
import morph/components/code

pub fn render(state: action.State) {
  div(
    [class("h-screen vstack")],
    [
      div([class("spacer")], []),
      // code.render(source),
      text("foo"),
      pre(
        [],
        code.render_text(
          state.source,
          "\n",
          code.Location([], Some(state.selection)),
        ),
      ),
      div([class("spacer")], []),
      div([class("cover bg-gray-100")], [text("morph")]),
    ],
  )
}
