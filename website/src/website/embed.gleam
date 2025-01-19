import eyg/sync/sync
import eygir/decode
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/list
import gleam/option.{None}
import gleam/string
import lustre
import morph/editable as e
import plinth/browser/document
import plinth/browser/element
import plinth/javascript/console
import website/components/snippet

pub fn run() {
  let scripts = document.query_selector_all("[type='application/json+eyg']")
  list.index_map(array.to_list(scripts), fn(script, i) {
    console.log(script)
    let id = "eyg" <> int.to_string(i)
    let json = element.inner_text(script)
    element.insert_adjacent_html(
      script,
      element.AfterEnd,
      "<div id=\"" <> id <> "\"></div>",
    )
    let json = string.replace(json, "&quot;", "\"")
    let assert Ok(source) = decode.from_json(json)
    // ORIGIN is not used when pulling from supabase
    let cache = sync.init(sync.test_origin)
    let source =
      e.from_expression(source)
      |> e.open_all
    let snippet = snippet.init(source, [], effects(), cache)
    let app = lustre.element(snippet.render_embedded(snippet, None))
    let assert Ok(_) = lustre.start(app, "#" <> id, Nil)
  })
}

fn effects() {
  []
}
// html.script([attribute.type_("application/json"), attribute.id("model")],
//           json.int(model)
//           |> json.to_string
//         )
