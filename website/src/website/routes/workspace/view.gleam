import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import morph/editable
import morph/projection
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
        state.ChoosingPackage -> modal([h.text("something")])
        state.EditingInteger(value:, rebuild:) -> modal([h.text("something")])
        state.EditingText(value:, rebuild:) ->
          modal([editor.render_text(value) |> element.map(state.InputMessage)])
        state.ReadingFromClipboard -> modal([h.text("something")])
        state.RunningShell(debug:) -> modal([h.text("something")])
        state.WritingToClipboard -> modal([h.text("something")])
        state.Editing ->
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
        h.div([a.class("max-w-sm border cover expand")], [
          h.div([], [h.text("modules")]),
          h.div(
            [],
            list.map(dict.to_list(state.modules), fn(module) {
              h.div([], [h.text(module.0)])
            }),
          ),
        ]),
        h.div([a.class("expand")], case state.focused {
          state.Repl -> [
            h.text("Shell"),
            snippet.render_projection(state.repl.projection, []),
          ]
          state.Module(filepath) -> [
            h.text(filepath),
            {
              let projection = case dict.get(state.modules, filepath) {
                Ok(buffer) -> buffer.projection
                Error(Nil) -> projection.all(editable.Vacant)
              }
              snippet.render_projection(projection, [])
            },
          ]
        }),
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
