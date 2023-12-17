import gleam/io
import gleam/int
import gleam/list
import gleam/listx
import gleam/javascript/array
import gleam/javascript/promise
import lustre/attribute.{class}
import lustre/effect
import lustre/element.{text}
import lustre/element/html.{br, div, input, span, table, tbody, td, tr}
import lustre/event.{on_click, on_input}
import datalog/browser/file
import datalog/browser/app/model.{Model, Source}
import datalog/ast
import datalog/browser/view/value

// import magpie/sources/yaml

pub fn render(index, relation, values) {
  div([class("cover")], [
    text("source"),
    display(values),
    div(
      [class("cusor bg-purple-300"), on_click(model.Wrap(add_row(_, index)))],
      [text("add row")],
    ),
    // css 
    // on drop look at file extension
    input([
      attribute.attribute("type", "file"),
      event.on("change", fn(event) {
        io.debug(event)
        file.event_files(event)
        |> array.to_list()
        |> list.map(fn(f) {
          file.name(f)
          |> io.debug
          file.mime(f)
          |> io.debug
          //   Need to dispatch event

          use t <- promise.map(file.text(f))
          io.debug(t)
        })
        //   yaml parsing is an option
        //   https://github.com/rollup/plugins/tree/master/packages/node-resolve
        //   yaml.parse_one(t)
        //   |> io.debug
        //   file is a type of blob
        Ok(
          model.Wrap(fn(model) {
            #(
              model,
              effect.from(fn(d) {
                // io.debug(d)
                d(model.Wrap(fn(m) { #(model.Model([]), effect.none()) }))
                Nil
              }),
            )
          }),
        )
      }),
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
  #(Model(..model, sections: sections), effect.none())
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
