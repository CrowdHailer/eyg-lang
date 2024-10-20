import gleam/int
import gleam/list
import lustre/attribute as a
import lustre/element.{text}
import lustre/element/html as h
import lustre/event
import morph/buffer

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
    h.input([
      a.class(
        "block w-full bg-transparent border-l-8 border-gray-700 focus:border-gray-300 p-1 outline-none",
      ),
      a.value(value),
      a.type_(type_),
      a.attribute("autofocus", "true"),
      event.on_keydown(buffer.KeyDown),
      event.on_input(buffer.UpdateInput),
    ]),
  ])
}
