import gleam/int
import gleam/list
import gleam/listx
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{br, div, span, table, tbody, td, tr}
import lustre/event.{on_click}
import datalog/browser/app/model.{Model, Source}
import datalog/ast
import datalog/browser/view/value

// list/list of terms

pub fn render(index, relation, values) {
  div([class("cover")], [
    text("source"),
    display(values),
    div([class("cusor bg-purple-300"), on_click(add_row(_, index))], [
      text("add row"),
    ]),
  ])
}

fn add_row(model, index) {
  let Model(sections) = model
  let assert Ok(sections) =
    listx.map_at(sections, index, fn(section) {
      let assert Source(r, table) = section
      Source(r, list.append(table, table))
    })
  Model(..model, sections: sections)
}

fn display(values) {
  table([], [tbody([], list.map(values, row))])
}

fn row(values) {
  tr([], list.map(values, cell))
}

fn cell(v) {
  let t = value.render(v)
  td([], [t])
}
