import eyg/analysis/inference/levels_j/contextual
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/editable
import morph/projection
import website/components/simple_debug
import website/components/snippet
import website/routes/editor
import website/routes/workspace/buffer
import website/routes/workspace/state

pub fn render(state: state.State) {
  h.div([a.class("h-full")], [
    h.div([], [
      case state.mode {
        state.Picking(picker:, ..) ->
          modal([
            editor.render_picker(picker) |> element.map(state.PickerMessage),
          ])
        state.ChoosingPackage(picker:, ..) ->
          modal([
            editor.render_picker(picker) |> element.map(state.PickerMessage),
          ])
        state.ChoosingModule(picker:, ..) ->
          modal([
            editor.render_picker(picker) |> element.map(state.PickerMessage),
          ])
        state.EditingInteger(value:, ..) ->
          modal([editor.render_number(value) |> element.map(state.InputMessage)])
        state.EditingText(value:, ..) ->
          modal([editor.render_text(value) |> element.map(state.InputMessage)])
        state.ReadingFromClipboard(..) -> element.none()
        state.WritingToClipboard -> element.none()
        state.RunningShell(occured:, awaiting:, debug:) ->
          modal([
            editor.render_effects_history(list.reverse(occured)),
            case awaiting {
              Some(_) -> h.div([], [h.text("running")])
              None ->
                h.div([], [h.text(simple_debug.reason_to_string(debug.0))])
            },
          ])
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
              h.div([], [h.text(module.0.0)])
            }),
          ),
        ]),
        h.div([a.class("expand")], case state.focused {
          state.Repl -> [
            h.text("Shell"),
            editor.render_previous(
              state.previous,
              state.PreviousMessage,
              state.UserSelectedPrevious,
            ),
            snippet.render_projection(
              state.repl.projection,
              contextual.all_errors(state.repl.analysis),
            ),
            h.div(
              [
                a.class("cover bg-red-300 px-2"),
                a.styles([#("max-height", "25vh"), #("overflow-y", "scroll")]),
              ],
              list.map(contextual.all_errors(state.repl.analysis), fn(error) {
                let #(reversed, reason) = error
                case reversed, reason {
                  // Vacant node at root or end of block are ignored.
                  [], error.Todo | [_], error.Todo -> element.none()
                  _, _ ->
                    h.div(
                      [
                        event.on_click(state.UserClickedOnPathReference(
                          reversed:,
                        )),
                      ],
                      [element.text(debug.reason(reason))],
                    )
                }
              }),
            ),
          ]
          state.Module(#(filepath, _) as with_ex) -> [
            h.text(filepath),
            ..{
              let buffer = case dict.get(state.modules, with_ex) {
                Ok(buffer) -> buffer
                Error(Nil) ->
                  buffer.from_projection(
                    projection.all(editable.Vacant),
                    contextual.pure(),
                  )
              }
              [
                snippet.render_projection(
                  buffer.projection,
                  contextual.all_errors(buffer.analysis),
                ),
                h.div(
                  [
                    a.class("cover bg-red-300 px-2"),
                    a.styles([
                      #("max-height", "25vh"),
                      #("overflow-y", "scroll"),
                    ]),
                  ],
                  list.map(contextual.all_errors(buffer.analysis), fn(error) {
                    let #(_path, reason) = error

                    h.div(
                      [
                        // event.on_click(
                      //   snippet.UserClickedPath(path)
                      //   |> shell.CurrentMessage,
                      // ),
                      ],
                      [element.text(debug.reason(reason))],
                    )
                  }),
                ),
              ]
            }
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
        "fixed inset-0 bg-white z-10 bg-opacity-80 flex items-center justify-center p-4",
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
