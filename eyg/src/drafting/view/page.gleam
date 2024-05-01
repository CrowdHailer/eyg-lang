import drafting/state
import drafting/view/picker
import eygir/annotated
import eygir/decode
import gleam/dynamic
import gleam/int
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/string
import gleam/stringx
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/editable
import morph/lustre/render
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
    drag.data_transfer(dynamic.unsafe_coerce(event))
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
    state.NoKeyBinding(key) ->
      string.concat(["No action bound for key '", key, "'"])
    state.ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
  }
}

pub fn render(app) {
  let state.State(context, source, mode, analysis) = app

  // containter for relative positioning
  h.div([a.class("relative font-mono")], [
    h.div([], case mode {
      state.Command(_) -> []
      state.Pick(picker, _rebuild) ->
        overlay([picker.render(picker, state.UpdatePicker)])
      state.EditText(value, _rebuild) -> overlay([string_input(value)])
      state.EditInteger(value, _rebuild) -> overlay([integer_input(value)])
    }),
    h.div(
      [
        a.class("flex flex-col justify-center min-h-screen p-4"),
        a.style([#("align-items", "center")]),
        event.on("dragover", handle_dragover),
        event.on("drop", handle_drop),
      ],
      [
        h.div([a.class("w-full max-w-4xl whitespace-nowrap")], [
          h.div(
            [
              a.class("outline-none"),
              a.attribute("tabindex", "0"),
              event.on_keydown(state.KeyDown),
              a.id("code"),
            ],
            [render.projection(source, True)],
          ),
          ..case mode {
            state.Command(Some(failure)) -> [
              h.div([a.class("border rounded border-red-500")], [
                text(fail_message(failure)),
              ]),
            ]
            state.Command(None) -> {
              [
                h.div(
                  [a.class("w-full orange-gradient text-white")],
                  list.map(
                    case analysis {
                      None -> []
                      Some(analysis) -> analysis.type_errors(analysis)
                    },
                    fn(e) {
                      let #(path, reason) = e
                      // analysis reverses the paths to correct order
                      // let path = list.reverse(path)
                      h.div([a.class("px-3")], [
                        h.a([event.on_click(state.JumpTo(path))], [
                          text(path_to_string(path)),
                        ]),
                        text(" "),
                        text(reason),
                      ])
                    },
                  ),
                ),
              ]
            }
            _ -> []
          }
        ]),
      ],
    ),
  ])
}

pub fn path_to_string(path) {
  list.map(path, int.to_string)
  |> string.join(",")
  |> stringx.wrap("[", "]")
}

pub fn string_input(value) {
  h.form([event.on_submit(state.Submit)], [
    h.div([a.class("w-full p-2")], []),
    h.input([
      a.class(
        "block w-full bg-transparent border-l-8 border-green-700 focus:border-green-300 px-2 py-2 outline-none",
      ),
      a.id("focus-input"),
      a.value(value),
      a.attribute("autofocus", "true"),
      event.on_keydown(state.KeyDown),
      event.on_input(state.UpdateInput),
    ]),
    h.hr([a.class("mx-40 my-3 border-green-700")]),
  ])
}

pub fn integer_input(value) {
  h.form([event.on_submit(state.Submit)], [
    h.div([a.class("w-full p-2")], []),
    h.input([
      a.class(
        "block w-full bg-transparent border-l-8 border-green-700 focus:border-green-300 px-2 py-2 outline-none",
      ),
      a.id("focus-input"),
      a.type_("number"),
      a.value(int.to_string(value)),
      a.attribute("autofocus", "true"),
      event.on_keydown(state.KeyDown),
      event.on_input(state.UpdateInput),
    ]),
    h.hr([a.class("mx-40 my-3 border-green-700")]),
  ])
}

fn overlay(content) {
  [
    h.div(
      [
        a.class(
          "absolute top-0 bottom-0 right-0 left-0 flex flex-col justify-center",
        ),
        a.style([#("align-items", "center"), #("backdrop-filter", "blur(3px)")]),
      ],
      [
        h.div(
          [a.class("bg-black text-white border-black max-w-2xl border w-full")],
          content,
        ),
      ],
    ),
  ]
}
