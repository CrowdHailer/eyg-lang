import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import website/components/snippet
import website/routes/editor
import website/routes/workspace/state

pub fn render(state: state.State) {
  h.div([a.class("h-full")], [
    h.div([], [
      case state.mode {
        state.Picking(picker:, ..) ->
          modal([
            editor.render_picker(picker) |> element.map(state.PickerMessage),
          ])
        _ ->
          case state.user_error {
            Some(reason) -> top([h.text(snippet.fail_message(reason))])
            None -> element.none()
          }
      },
    ]),
    h.div(
      [
        a.class("h-full hstack gap-8 p-4"),
      ],
      [
        h.div([a.class("max-w-sm border cover expand")], [h.text("hello")]),
        h.div([a.class("expand")], [
          h.text("Shell"),
          snippet.render_projection(state.repl.projection, []),
        ]),
      ],
    ),
  ])
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

fn top(children) {
  h.div(
    [
      a.class(
        "fixed inset-x-0 bg-white bg-opacity-80 flex items-center justify-center p-4",
      ),
    ],
    [
      h.div(
        [a.class("bg-white max-w-xl w-full px-2 py-1 rounded bg-red-300")],
        children,
      ),
    ],
  )
}
