import gleam/list
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h

pub fn render(language: String, content: String) -> element.Element(msg) {
  case string.trim(language) {
    // "eyg" -> eyg(content)
    // "eyg.json" -> eyg_json(content)
    _ -> plain(language, content)
  }
}

// always render plain for now as we're showing text syntax
// TODO reimplement once structural editor and text syntax match
// fn eyg(content: String) {
//   case parser.all_from_string(content) {
//     Ok(source) -> highlighted(source)
//     Error(_) -> plain("eyg", content)
//   }
// }

// fn eyg_json(content: String) {
//   case json.parse(content, dag_json.decoder(Nil)) {
//     Ok(source) -> highlighted(source)
//     Error(_) ->
//       case dag_json.from_block(bit_array.from_string(content)) {
//         Ok(source) -> highlighted(source)
//         Error(_) -> plain("eyg.json", content)
//       }
//   }
// }

// fn highlighted(source) {
//   h.pre(
//     [
//       a.class("language-eyg"),
//       a.styles(
//         list.append(ui.code_area_styles, [
//           #("height", "auto"),
//           #("margin-top", "0"),
//           #("margin-bottom", "0"),
//         ]),
//       ),
//     ],
//     [
//       source
//       |> editable.from_annotated
//       |> projection.all
//       |> ui.render_projection([]),
//     ],
//   )
// }

fn plain(language: String, content: String) {
  let class = case string.trim(language) {
    "" -> []
    language -> [a.class("language-" <> language)]
  }

  h.pre(
    [
      a.styles([
        #("color", "#e2e8f0"),
        #("background-color", "#2d3748"),
        #("overflow-x", "auto"),
        #("font-size", "14px"),
        #("line-height", "1.7142857"),
        #("margin-top", "27px"),
        #("margin-bottom", "27px"),
        #("border-radius", "6px"),
        #("padding-top", "13px"),
        #("padding-right", "18px"),
        #("padding-bottom", "13px"),
        #("padding-left", "18px"),
      ]),
    ],
    [
      h.code(
        list.append(class, [
          a.styles([
            #("background-color", "transparent"),
            #("border-width", "0"),
            #("border-radius", "0"),
            #("padding", "0"),
            #("font-weight", "400"),
            #("color", "inherit"),
            #("font-size", "inherit"),
            #("font-family", "inherit"),
            #("line-height", "inherit"),
          ]),
        ]),
        [element.text(content)],
      ),
    ],
  )
}
