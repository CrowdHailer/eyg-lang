//// Concepts and getting started, the text is in `documentation.md` next to this module.

import gleam/list
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import mysig/asset
import mysig/html
import pamphlet
import pamphlet/lustre
import simplifile
import website/components
import website/guide_highlight
import website/routes/glasshouse/layout

const source = "src/website/routes/glasshouse/documentation.md"

pub fn page() {
  let assert Ok(text) = simplifile.read(source)
  use pamphlet_style <- asset.do(asset.load("src/website/routes/pamphlet.css"))
  use content <- asset.do(layout.page(
    "/glasshouse/documentation",
    "Glasshouse documentation",
    "Record, inspect, replay and export EYG programs and agent sessions.",
    [html.stylesheet(asset.src(pamphlet_style))],
    body(text),
  ))
  asset.done(element.to_document_string(content))
}

fn body(text: String) -> List(Element(msg)) {
  let #(_, document) = pamphlet.parse(text)
  let article =
    lustre.to_lustre(document, guide_highlight.renderer())(fn(x) { x })
  [
    components.header(),
    layout.nav("/glasshouse/documentation"),
    h.div([a.class("gh-hero")], [
      h.div([a.class("gh-section")], [
        h.h1([a.class("gh-section-title")], [element.text("Documentation")]),
        h.p([a.class("gh-hero-lead")], [
          element.text(
            "Keep pinned code and effect journals together, then inspect and replay the recorded runs.",
          ),
        ]),
        flow(),
      ]),
    ]),
    h.div([a.class("gh-docs")], [
      h.nav([a.class("gh-toc")], toc(text)),
      h.article([a.class("pamphlet gh-article")], [article]),
    ]),
    components.footer(),
  ]
}

fn flow() {
  h.div([a.class("gh-flow")], [
    flow_step(
      "bg-green-1",
      "Record",
      "Run code and every effect is journaled, imports pinned by hash.",
    ),
    flow_step(
      "bg-blue-1",
      "Archive",
      "One JSON file holds the session and every value it touched.",
    ),
    flow_step(
      "bg-yellow-1",
      "Inspect",
      "Step through effects, files and context in the debugger.",
    ),
    flow_step(
      "bg-pink-1",
      "Replay",
      "Run the pinned code again, every effect answered from the trace.",
    ),
  ])
}

fn flow_step(colour, title, text) {
  h.div([a.class("gh-flow-step " <> colour)], [
    h.strong([], [element.text(title)]),
    element.text(text),
  ])
}

// Links to every section, using the identifiers the djot renderer gives headings.
fn toc(text: String) -> List(Element(msg)) {
  string.split(text, "\n")
  |> list.filter_map(fn(line) {
    case line {
      "## " <> title ->
        Ok(
          h.div([a.class("gh-toc-group")], [
            h.a([a.href("#" <> heading_id(title))], [element.text(title)]),
          ]),
        )
      "### " <> title ->
        Ok(h.a([a.href("#" <> heading_id(title))], [element.text(title)]))
      _ -> Error(Nil)
    }
  })
}

pub fn heading_id(title: String) -> String {
  string.split(title, " ")
  |> list.map(fn(word) {
    string.to_graphemes(word)
    |> list.filter(fn(c) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
        c,
      )
    })
    |> string.concat
  })
  |> list.filter(fn(word) { word != "" })
  |> string.join("-")
}
