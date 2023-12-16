import gleam/list
import lustre/element.{text}
import lustre/attribute.{class}
import lustre/element/html.{div, p}
import datalog/browser/app/model
import datalog/browser/view/query

pub fn render(model) {
  let model.Model(sections) = model
  div([class("vstack wrap")], [
    div([class("absolute  bottom-0 left-0 right-0 top-0")], []),
    div([class("absolute border p-4 bg-white w-full max-w-xl rounded")], [
      p([], [text("floating modal")]),
      p([], [text("floating modal")]),
    ]),
    div(
      [
        // on_keydown(fn(key) { fn(state) { state + 1 } }),
        attribute.attribute("tabindex", "-1"),
        class("vstack w-full max-w-2xl mx-auto"),
      ],
      list.index_map(sections, section),
    ),
  ])
}

fn section(index, section) {
  case section {
    model.Query(q) -> query.render(index, q)
    model.Paragraph(content) -> p([], [text(content)])
  }
}
