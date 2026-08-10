import eyg/analysis/inference/levels_j/contextual
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleroglero/outline
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/buffer
import morph/editable
import morph/projection
import website/command
import website/components/output
import website/manipulation
import website/routes/editor/view as editor_view
import website/routes/workspace/state
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
            h.text(string.inspect(status)),
            // case status {
          //   // run.Concluded(return) ->
          //   //   h.div([], [h.text(string.inspect(return))])
          //   // run.Exception(reason) ->
          //   //   h.div([], [h.text(simple_debug.describe(reason))])
          //   // run.Aborted(message) -> h.div([], [h.text(message)])
          //   // run.Handling(task_id: _, env: _, k: _) ->
          //   //   h.div([], [h.text("running")])
          //   // run.Pending(..) -> h.div([], [h.text("running")])
          //   _ -> todo
          // },
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
              render_previous(
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

pub fn render_previous(
  previous,
  on_readonly,
  on_previous,
) -> element.Element(a) {
  h.div([a.class("expand cover font-mono bg-gray-100 overflow-auto")], {
    let count = list.length(previous) - 1
    list.index_map(list.reverse(previous), fn(p, i) {
      let i = count - i
      case p {
        state.Previous(value, effects, buffer) ->
          h.div([a.class("mx-2 border-t border-gray-600 border-dashed")], [
            h.div([a.class("relative pr-8")], [
              h.div([a.class("flex-grow whitespace-nowrap overflow-auto")], [
                ui.code(buffer.projection, buffer.analysis, on_readonly(i, _)),
              ]),
              h.button(
                [
                  a.class("absolute top-0 right-0 w-6"),
                  event.on_click(on_previous(1)),
                ],
                [outline.arrow_path()],
              ),
            ]),
            editor_view.render_effects_history(effects),
            case value {
              Some(value) ->
                h.div([a.class(" max-h-60 overflow-auto")], [
                  // would need to be flex to show inline
                  // h.span([a.class("font-bold")], [element.text("> ")]),
                  output.render(value),
                ])
              None -> element.none()
            },
          ])
      }
    })
  })
}
