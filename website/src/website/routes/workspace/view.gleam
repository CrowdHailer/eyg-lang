import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import website/components/snippet
import website/routes/editor
import website/routes/workspace/state

pub fn render(state: state.State) {
  h.div(
    [
      a.class("hstack gap-8 p-4"),
    ],
    [
      case state.mode {
        state.Picking(picker:, ..) ->
          modal([
            editor.render_picker(picker) |> element.map(state.PickerMessage),
          ])
        _ -> element.none()
      },
      h.div([a.class("max-w-sm border cover expand")], [h.text("hello")]),
      h.div([a.class("expand")], [
        h.text("Shell"),
        snippet.render_projection(state.repl.projection, []),
      ]),
    ],
  )
}

fn modal(children) {
  h.div(
    [
      a.class(
        "fixed inset-0 bg-white bg-opacity-80 flex items-center justify-center p-4",
      ),
    ],
    [
      h.div([a.class("bg-white max-w-xl w-full p-6")], children),
    ],
  )
}
