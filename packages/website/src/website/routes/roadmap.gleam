import lustre/attribute
import lustre/element
import lustre/element/html

pub fn render() -> String {
  html.html([], [
    html.head([], [
      html.title([], "Roadmap"),
      html.script(
        [attribute.type_("module")],
        "import { main } from \"/src/website.gleam\"; main()",
      ),
    ]),
    html.body([], [
      html.h1([], [element.text("Roadmap1")]),
      html.p([], [element.text("Here's what's coming...")]),
    ]),
  ])
  |> element.to_document_string
}
