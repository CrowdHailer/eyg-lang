import gleam/dict
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import lustre/element.{text}
import lustre/attribute.{class}
import lustre/effect
import lustre/element/html.{button, div, p}
import lustre/event.{on_click}
import datalog/ast
import datalog/browser/app/model.{Model}
import datalog/browser/view/source
import datalog/browser/view/query

pub fn render(model) -> element.Element(model.Wrap) {
  let Model(sections, editing) = model
  div([class("vstack wrap")], [
    // div([class("absolute  bottom-0 left-0 right-0 top-0")], []),
    // div([class("absolute border p-4 bg-white w-full max-w-xl rounded")], [
    //   p([], [text("floating modal")]),
    //   p([], [text("floating modal")]),
    // ]),
    div(
      [
        // on_keydown(fn(key) { fn(state) { state + 1 } }),
        // attribute.attribute("tabindex", "-1"),
        class("vstack w-full max-w-2xl mx-auto"),
      ],
      list.flatten(list.index_map(sections, section(editing))),
    ),
  ])
}

fn section(editing) {
  fn(index, section) {
    [
      case section {
        model.Query(q, output) -> {
          let state = case editing {
            Some(#(target, text, r)) if target == index -> Some(#(text, r))
            _ -> None
          }
          query.render(index, q, state, output)
        }

        model.Source(relation, table) -> source.render(index, relation, table)
        model.Paragraph(content) -> p([], [text(content)])
        _ -> todo
      },
      menu(index),
    ]
  }
}

fn menu(index) {
  div([class("hstack")], [
    button(
      [
        class("cursor bg-green-300 rounded"),
        on_click(model.Wrap(insert_query(_, index + 1))),
      ],
      [text("new plaintext")],
    ),
    button(
      [
        class("cursor bg-green-300 rounded"),
        on_click(model.Wrap(insert_source(_, index + 1))),
      ],
      [text("new source")],
    ),
  ])
}

fn insert_query(model, index) {
  let Model(sections, ..) = model
  let new = model.Query([], Ok(dict.new()))
  let sections = listx.insert_at(sections, index, [new])
  #(Model(..model, sections: sections), effect.none())
}

fn insert_source(model, index) {
  let Model(sections, ..) = model
  let new = model.Source("Foo", [[ast.I(2), ast.I(100), ast.S("hey")]])
  let sections = listx.insert_at(sections, index, [new])
  #(Model(..model, sections: sections), effect.none())
}
