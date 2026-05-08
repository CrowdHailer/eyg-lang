import eyg/analysis/inference/levels_j/contextual
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/interpreter/simple_debug
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/buffer
import morph/editable
import morph/projection
import website/command
import website/manipulation
import website/routes/editor/view as editor_view
import website/routes/workspace/state
import website/run
import website/ui

pub fn render(state: state.State) {
  h.div([a.class("h-full")], [
    h.div([], [
      case state.mode {
        state.Manipulating(manipulation.PickSingle(picker, _)) ->
          modal([
            editor_view.render_picker(picker)
            |> element.map(state.PickerMessage),
          ])
        state.Manipulating(manipulation.PickCid(picker, _)) ->
          modal([
            editor_view.render_picker(picker)
            |> element.map(state.PickerMessage),
          ])
        state.Manipulating(manipulation.PickRelease(picker, _)) ->
          modal([
            editor_view.render_picker(picker)
            |> element.map(state.PickerMessage),
          ])
        state.Manipulating(manipulation.EnterInteger(value, ..)) ->
          modal([
            editor_view.render_number(value) |> element.map(state.InputMessage),
          ])
        state.Manipulating(manipulation.EnterText(value, ..)) ->
          modal([
            editor_view.render_text(value) |> element.map(state.InputMessage),
          ])
        state.ReadingFromClipboard(..) -> element.none()
        state.WritingToClipboard -> element.none()
        state.RunningShell(occured:, status:) ->
          modal([
            editor_view.render_effects_history(list.reverse(occured)),
            case status {
              run.Concluded(return) ->
                h.div([], [h.text(string.inspect(return))])
              run.Exception(reason) ->
                h.div([], [h.text(simple_debug.describe(reason))])
              run.Aborted(message) -> h.div([], [h.text(message)])
              run.Handling(task_id: _, env: _, k: _) ->
                h.div([], [h.text("running")])
              run.Pending(..) -> h.div([], [h.text("running")])
            },
          ])
        state.SigningPayload(..) -> modal([h.text("signing")])
        state.Editing ->
          case state.user_error {
            Some(reason) -> top([h.text(command.fail_message(reason))])
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
          h.div([], [h.text("Modules")]),
          h.div(
            [],
            list.map(dict.to_list(state.modules), fn(module) {
              let #(filename, _buffer) = module
              let #(name, state.EygJson) = filename
              h.div([event.on_click(state.UserClickedOnModule(filename:))], [
                h.text(name),
              ])
            }),
          ),
        ]),
        h.div(
          [
            a.class("expand"),
            a.styles([#("max-height", "100%"), #("overflow", "scroll")]),
          ],
          case state.focused {
            state.Repl -> [
              h.text("Shell"),
              editor_view.render_previous(
                state.previous,
                state.PreviousMessage,
                state.UserSelectedPrevious,
              ),
              ui.render_projection(
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
                  ui.render_projection(
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
          },
        ),
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
