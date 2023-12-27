import gleam/dynamic
import gleam/list
import gleam/uri
import gleam/http/request
import lustre/attribute.{class, readonly, value}
import lustre/element.{text}
import lustre/element/html.{div, input, p, span, table, tbody, td, tr}
import datalog/browser/view/value

pub fn render(req, relation, data) {
  let source = uri.to_string(request.to_uri(req))
  // share display code with source cell where source is entered in place and has from file reference
  // sort out loading triples with number/string/any types
  // parquet data format, CSV -> choices
  // How to show that something is Tagged
  // show type inference over a cell
  // TODO try parsing with nibble.
  // load some data from OAuth, calendar?
  // TODO show number of rows, make a Focus mode
  // TODO show loading time
  div(
    [
      class(
        "vstack wrap left bg-white border-2 border-black rounded w-full neo-shadow",
      ),
    ],
    [
      div([class("hstack tight")], [
        span([class("bg-black text-white")], [text("Remote")]),
        input([
          class("w-full m-0 bg-gray-800 text-white"),
          readonly(True),
          value(dynamic.from(source)),
        ]),
      ]),
      display(list.take(data, 10)),
    ],
  )
}

pub fn display(values) {
  table([], [tbody([], list.map(values, row))])
}

fn row(values) {
  tr([], list.map(values, cell))
}

fn cell(v) {
  let t = value.render(v)
  td([], [t])
}
