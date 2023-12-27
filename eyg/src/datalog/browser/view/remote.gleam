import gleam/list
import lustre/element.{text}
import lustre/element/html.{p, table, tbody, td, tr}
import datalog/browser/view/value

pub fn render(request, relation, data) {
  // TODO show loading time
  // TODO show number of rows, make a Focus mode
  // Load all remotes at startup time
  // share display code with source cell where source is entered in place and has from file reference
  // sort out loading triples with number/string/any types
  // show type inference over a cell
  p([], [text("remote"), display(list.take(data, 10))])
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
