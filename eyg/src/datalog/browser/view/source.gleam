import datalog/ast
import datalog/browser/app/model.{Model, Source}
import datalog/browser/view/value
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/listx
import lustre/attribute.{class, readonly, value}
import lustre/effect
import lustre/element.{text}
import lustre/element/html.{
  br, div, input, span, table, tbody, td, th, thead, tr,
}
import lustre/event.{on_click, on_input}

// import magpie/sources/yaml

pub fn render(index, relation, headings, values) {
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
          value(relation),
        ]),
      ]),
      display(headings, values),
    ],
  )
  // div(
  //   [class("cusor bg-purple-300"), on_click(model.Wrap(add_row(_, index)))],
  //   [text("add row")],
  // ),
  // css
  // on drop look at file extension
  // input([
  //   attribute.attribute("type", "file"),
  //   event.on("change", fn(event) {
  //     io.debug(event)
  //     file.event_files(event)
  //     |> array.to_list()
  //     |> list.map(fn(f) {
  //       file.name(f)
  //       |> io.debug
  //       file.mime(f)
  //       |> io.debug
  //       //   Need to dispatch event

  //       use t <- promise.map(file.text(f))
  //       io.debug(t)
  //     })
  //     //   yaml parsing is an option
  //     //   https://github.com/rollup/plugins/tree/master/packages/node-resolve
  //     //   yaml.parse_one(t)
  //     //   |> io.debug
  //     Ok(
  //       model.Wrap(fn(model) {
  //         #(
  //           model,
  //           effect.from(fn(d) {
  //             // io.debug(d)
  //             d(model.Wrap(fn(m) { #(model, effect.none()) }))
  //             Nil
  //           }),
  //         )
  //       }),
  //     )
  //   }),
  // ]),
}

fn add_row(model, index) {
  let Model(sections: sections, ..) = model
  let assert Ok(sections) =
    listx.map_at(sections, index, fn(section) {
      let assert Source(r, headings, table) = section
      Source(r, headings, list.append(table, table))
    })
  #(Model(..model, sections: sections), effect.none())
}

pub fn display(headings, values) {
  table([], [
    thead(
      [class("bg-gray-200")],
      list.map(headings, fn(h) { th([class("px-2")], [text(h)]) }),
    ),
    tbody([], list.map(values, row)),
  ])
}

fn row(values) {
  tr([], list.map(values, cell))
}

fn cell(v) {
  let t = value.render(v)
  td([class("border text-right px-2")], [t])
}
