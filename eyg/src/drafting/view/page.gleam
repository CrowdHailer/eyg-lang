import eyg/shell/buffer
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html as h
import lustre/event

// fn handle_dragover(event) {
//   event.prevent_default(event)
//   event.stop_propagation(event)
//   Error([])
// }

// needs to handle dragover otherwise browser will open file
// https://stackoverflow.com/questions/43180248/firefox-ondrop-event-datatransfer-is-null-after-update-to-version-52
// fn handle_drop(event) {
//   event.prevent_default(event)
//   event.stop_propagation(event)
//   let files =
//     drag.data_transfer(dynamicx.unsafe_coerce(event))
//     |> drag.files
//     |> array.to_list()
//   case files {
//     [file] -> {
//       let work =
//         promise.map(file.text(file), fn(content) {
//           let assert Ok(source) = decode.from_json(content)
//           //  going via annotated is inefficient
//           let source = annotated.add_annotation(source, Nil)
//           let source = editable.from_annotated(source)
//           Ok(source)
//         })

//       Ok(state.Loading(work))
//     }
//     _ -> {
//       console.log(#(event, files))
//       Error([])
//     }
//   }
// }

pub fn fail_message(reason) {
  case reason {
    buffer.NoKeyBinding(key) ->
      string.concat(["No action bound for key '", key, "'"])
    buffer.ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
  }
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
    #("y", "copy"),
    #("Y", "paste"),
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
    #("j", "insert a builtin function"),
    #("k", "collapse/uncollapse code section"),
    #("l", "create a list"),
    #("#", "insert a reference"),
    // "z" -> TODO need to use the same history stuff
    // "x" ->
    #("c", "call function this function"),
    #("v", "create a variable"),
    #("b", "create a array of bytes"),
    #("n", "create a number"),
    #("m", "create a match expression"),
    #("M", "insert an open match expression"),
    #(",", "add element in a list"),
    #(".", "open a list for extension"),
  ]
}

pub fn string_input(value) {
  input(value, "text")
}

pub fn integer_input(value) {
  let raw = case value {
    0 -> ""
    _ -> int.to_string(value)
  }
  input(raw, "number")
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
