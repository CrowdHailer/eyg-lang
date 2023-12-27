import gleam/dynamic
import gleam/list
import gleam/uri
import gleam/http/request
import lustre/attribute.{class, readonly, value}
import lustre/element.{text}
import lustre/element/html.{input, p, table, tbody, td, tr}
import datalog/browser/view/value

pub fn render(req, relation, data) {
  let source = uri.to_string(request.to_uri(req))
  // TODO show loading time
  // TODO show number of rows, make a Focus mode
  // share display code with source cell where source is entered in place and has from file reference
  // sort out loading triples with number/string/any types
  // show type inference over a cell
  p([class("cover")], [
    input([class("w-full border"), readonly(True), value(dynamic.from(source))]),
    display(list.take(data, 10)),
  ])
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
