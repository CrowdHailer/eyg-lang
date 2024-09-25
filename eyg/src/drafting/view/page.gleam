import drafting/state
import drafting/view/picker
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/shell/buffer
import eyg/sync/sync
import eygir/annotated
import eygir/decode
import gleam/dynamic
import gleam/dynamicx
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/stringx
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/editable
import morph/lustre/render
import morph/projection as p
import plinth/browser/drag
import plinth/browser/file
import plinth/javascript/console

fn handle_dragover(event) {
  event.prevent_default(event)
  event.stop_propagation(event)
  Error([])
}

// needs to handle dragover otherwise browser will open file
// https://stackoverflow.com/questions/43180248/firefox-ondrop-event-datatransfer-is-null-after-update-to-version-52
fn handle_drop(event) {
  event.prevent_default(event)
  event.stop_propagation(event)
  let files =
    drag.data_transfer(dynamicx.unsafe_coerce(event))
    |> drag.files
    |> array.to_list()
  case files {
    [file] -> {
      let work =
        promise.map(file.text(file), fn(content) {
          let assert Ok(source) = decode.from_json(content)
          //  going via annotated is inefficient
          let source = annotated.add_annotation(source, Nil)
          let source = editable.from_annotated(source)
          Ok(source)
        })

      Ok(state.Loading(work))
    }
    _ -> {
      console.log(#(event, files))
      Error([])
    }
  }
}

pub fn fail_message(reason) {
  case reason {
    buffer.NoKeyBinding(key) ->
      string.concat(["No action bound for key '", key, "'"])
    buffer.ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
  }
}

pub fn render(app) {
  let state.State(cache, buffer, analysis, failure, show_help, _auto_analyse) =
    app

  // containter for relative positioning
  h.div([a.class("font-mono min-h-screen flex flex-col")], [
    case cache.pending {
      [] -> h.div([], [])
      [#(k, _)] -> h.div([a.class("bg-gray-300")], [text("loading #"), text(k)])
      [#(k, _), ..rest] ->
        h.div([a.class("bg-gray-300")], [
          text("loading #"),
          text(k),
          text(" and "),
          text(int.to_string(list.length(rest))),
          text(" others."),
        ])
    },
    h.div(
      [
        a.class("flex justify-center flex-1"),
        a.style([#("align-items", "center")]),
        event.on("dragover", handle_dragover),
        event.on("drop", handle_drop),
      ],
      [
        h.div(
          [
            a.class("w-full max-w-3xl relative flex flex-col justify-center"),
            a.style([#("align-self", "stretch")]),
          ],
          [
            h.div([], case buffer.1 {
              buffer.Command(_) -> []
              buffer.Pick(picker, _rebuild) ->
                overlay([picker.render(picker, buffer.UpdatePicker)])
              buffer.EditText(value, _rebuild) ->
                overlay([input(value, "text")])
              buffer.EditInteger(value, _rebuild) ->
                overlay([input(int.to_string(value), "number")])
            }),
            h.div(
              [
                a.class("outline-none whitespace-nowrap"),
                a.attribute("tabindex", "0"),
                event.on("keydown", fn(event) {
                  event.prevent_default(event)
                  dynamic.field("key", dynamic.string)(event)
                  |> result.map(buffer.KeyDown)
                }),
                a.id("code"),
              ],
              [render.projection(buffer.0, True)],
            ),
            case failure, buffer.1 {
              Error(reason), _ ->
                h.div(
                  [a.class("w-full my-4 border p-1 rounded border-red-500")],
                  [text(reason)],
                )
              _, buffer.Command(Some(failure)) ->
                h.div(
                  [a.class("w-full my-4 border p-1 rounded border-red-500")],
                  [text(fail_message(failure))],
                )

              _, buffer.Command(None) -> {
                case analysis {
                  None ->
                    case p.blank(buffer.0) {
                      True ->
                        h.div(
                          [a.class("w-full my-4 bg-gray-200 py-1 px-2 rounded")],
                          [
                            h.div([a.class("border rounded ")], [
                              h.h4([a.class("text-2xl my-4 text-center")], [
                                text("EYG structural editor"),
                              ]),
                              h.p([], [
                                text(
                                  "Start editing EYG programs faster. Don't type text instead directly modify the program.",
                                ),
                              ]),
                              h.p([], [
                                text(
                                  "Click on the space above to start coding or drag in a source file to start editing",
                                ),
                              ]),
                            ]),
                          ],
                        )
                      False ->
                        h.div([a.class("w-full my-4 bg-gray-200 p-1 rounded")], [
                          h.div([a.class("border rounded")], [
                            text("Press Enter to type check"),
                          ]),
                        ])
                    }
                  Some(analysis) ->
                    case analysis.type_errors(analysis) {
                      [] ->
                        h.div([a.class("w-full my-4 bg-gray-200 p-1 rounded")], [
                          h.div([], [
                            case analysis.do_type_at(analysis, buffer.0) {
                              Ok(t) -> text(debug.mono(t))
                              _ -> element.none()
                            },
                          ]),
                        ])
                      errors ->
                        h.div([], [
                          h.div([], [
                            case analysis.do_type_at(analysis, buffer.0) {
                              Ok(t) -> text(debug.mono(t))
                              _ -> element.none()
                            },
                          ]),
                          ..list.map(errors, fn(e) {
                            let #(path, reason) = e
                            // analysis reverses the paths to correct order
                            // let path = list.reverse(path)
                            case reason {
                              error.SameTail(_, _) -> {
                                io.debug(
                                  "this error I dont understand shouldnt occur",
                                )
                                element.none()
                              }
                              _ ->
                                h.div(
                                  [
                                    a.class(
                                      "w-full my-4 orange-gradient p-1 rounded",
                                    ),
                                  ],
                                  [
                                    h.div([a.class("px-3")], [
                                      h.a(
                                        [event.on_click(buffer.JumpTo(path))],
                                        [text(path_to_string(path))],
                                      ),
                                      text(" "),
                                      text(debug.reason(reason)),
                                    ]),
                                  ],
                                )
                            }
                          })
                        ])
                    }
                }
              }
              _, _ -> element.none()
            },
          ],
        )
          |> element.map(state.Buffer),
        h.div(
          [
            a.class(
              "w-full max-w-md sticky top-0 flex flex-col justify-center p-2",
            ),
            a.style([#("align-self", "stretch")]),
          ],
          [
            case show_help {
              True ->
                h.div(
                  [
                    a.class(
                      "border border-blue-800 bg-white rounded p-2 shadow-xl",
                    ),
                  ],
                  [
                    h.h1([a.class("text-xl font-bold")], [text("commands")]),
                    key_references(),
                  ],
                )
              False -> element.none()
            },
          ],
        ),
      ],
    ),
  ])
}

pub fn key_references() {
  h.div([], list.map(bindings(), key_binding))
}

fn key_binding(binding) {
  let #(k, action) = binding
  h.div([a.class("")], [
    h.span([a.class("font-bold")], [text(k)]),
    h.span([], [text(": ")]),
    h.span([], [text(action)]),
  ])
}

pub fn bindings() {
  [
    #("?", "show/hide help"),
    #("SPACE", "jump to next vacant"),
    #("w", "call a function with this term"),
    #("E", "insert an assignment before this term"),
    #("e", "assign this term"),
    #("r", "create a record"),
    #("t", "create a tagged term"),
    // #("y", "extend_before"),
    // "u" ->
    #("i", "edit this term"),
    #("o", "overwrite record fields"),
    #("p", "create a perform effect"),
    #("a", "increase the selection"),
    #("s", "create a string"),
    #("d", "delete this code"),
    #("f", "wrap in a function"),
    #("g", "select a field"),
    #("h", "create an effect handler"),
    #("j", "insert_builtin"),
    #("k", "collapse/uncollapse code section"),
    #("l", "create a list"),
    #("#", "insert a reference"),
    // "z" -> TODO need to use the same history stuff
    // "x" ->
    #("c", "call function this function"),
    #("v", "create a variable"),
    #("b", "create a array of bytes"),
    #("n", "create a number"),
    #("m", "create a match statement"),
    #("M", "insert_open_case"),
    #(".", "open a list for extension"),
  ]
}

pub fn path_to_string(path) {
  list.map(path, int.to_string)
  |> string.join(",")
  |> stringx.wrap("[", "]")
}

pub fn string_input(value) {
  input(value, "text")
}

pub fn integer_input(value) {
  input(int.to_string(value), "number")
}

fn input(value, type_) {
  h.form([event.on_submit(buffer.Submit)], [
    // h.div([a.class("w-full p-2")], []),
    h.input([
      a.class(
        "block w-full bg-transparent border-l-8 border-gray-700 focus:border-gray-300 p-1 outline-none",
      ),
      a.id("focus-input"),
      a.value(value),
      a.type_(type_),
      a.attribute("autofocus", "true"),
      event.on_keydown(buffer.KeyDown),
      event.on_input(buffer.UpdateInput),
    ]),
    // h.hr([a.class("mx-40 my-1 border-gray-700")]),
  ])
}

fn overlay(content) {
  [
    h.div(
      [
        a.class(
          "absolute top-0 bottom-0 right-0 left-0 flex flex-col justify-center",
        ),
        a.style([#("align-items", "center")]),
      ],
      [
        h.div(
          [a.class("bg-white border-blue-800 border shadow-xl rounded w-full")],
          content,
        ),
      ],
    ),
  ]
}
