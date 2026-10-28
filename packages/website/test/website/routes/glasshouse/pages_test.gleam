import eyg/parser
import gleam/list
import gleam/string
import lustre/element
import pamphlet
import pamphlet/lustre
import simplifile
import website/guide_highlight
import website/routes/glasshouse
import website/routes/glasshouse/documentation

pub fn every_page_builds_test() {
  glasshouse.route()
}

pub fn acquisition_article_examples_parse_test() {
  let assert Ok(html) =
    simplifile.read("src/website/routes/glasshouse/runtime-acquisition.html")
  let assert [_, first, ..rest] =
    string.split(html, "<code class=\"language-eyg\">")
  list.each([first, ..rest], fn(section) {
    let assert Ok(#(code, _)) = string.split_once(section, "</code>")
    let code =
      code
      |> string.replace("&gt;", ">")
      |> string.replace("&lt;", "<")
      |> string.replace("&amp;", "&")
    let assert Ok(_) = parser.all_from_string(code)
  })
}

pub fn contents_link_to_every_heading_test() {
  let assert Ok(text) =
    simplifile.read("src/website/routes/glasshouse/documentation.md")
  let #(_, document) = pamphlet.parse(text)
  let html =
    lustre.to_lustre(document, guide_highlight.renderer())(fn(x) { x })
    |> element.to_string
  let headings =
    string.split(text, "\n")
    |> list.filter_map(fn(line) {
      case line {
        "## " <> title | "### " <> title -> Ok(title)
        _ -> Error(Nil)
      }
    })
  let assert [_, ..] = headings
  assert list.all(headings, fn(title) {
    string.contains(html, "id=\"" <> documentation.heading_id(title) <> "\"")
  })
}
