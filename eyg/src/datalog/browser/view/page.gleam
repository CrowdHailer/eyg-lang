import gleam/io
import gleam/dynamic
import gleam/dict
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/string
import gleam/uri
import gleam/http/request
import gleam/fetch
import gleam/javascript/promise
import lustre/element.{text}
import lustre/attribute.{class}
import lustre/effect
import lustre/element/html.{button, div, form, input, p}
import lustre/event.{on_click, on_input}
import datalog/ast
import datalog/browser/app/model.{Model}
import datalog/browser/view/source
import datalog/browser/view/query
import datalog/browser/view/remote

pub fn render(model) -> element.Element(model.Wrap) {
  let Model(sections, mode) = model
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
      list.flatten(list.index_map(sections, section(mode))),
    ),
  ])
}

fn section(mode) {
  fn(section, index) {
    [
      case section {
        model.Query(q, output) -> {
          let state = case mode {
            model.Editing(target, text, r) if target == index ->
              Some(#(text, r))
            _ -> None
          }
          query.render(index, q, state, output)
        }

        model.Source(relation, table) -> source.render(index, relation, table)
        model.Paragraph(content) -> p([], [text(content)])
        model.RemoteSource(request, relation, data) ->
          remote.render(request, relation, data)
      },
      subsection(index, mode),
    ]
  }
}

fn submit_remote(state) {
  let Model(sections, mode) = state
  let assert model.SouceSelection(i, raw) = mode
  let i = i + 1
  let assert Ok(source) = uri.parse(raw)
  let assert Ok(req) = request.from_uri(source)
  let sections = listx.insert_at(sections, i, [model.RemoteSource(req, "", [])])
  let state = Model(sections, model.Viewing)
  // keep request in location for remote
  let task = fetch.send(req)
  #(
    state,
    effect.from(fn(dispatch) {
      promise.await(task, fn(r) {
        let assert Ok(r) = r
        use r <- promise.map(fetch.read_text_body(r))
        let assert Ok(r) = r

        let lines = string.split(r.body, "\n")
        let data = list.map(lines, string.split(_, ","))
        let table = list.map(data, list.map(_, ast.S))
        io.debug(table)
        // string split twice works. but how do I put it into the types
        dispatch(
          model.Wrap(fn(state) {
            let Model(sections, mode) = state
            let assert Ok(sections) =
              listx.map_at(sections, i, fn(s) {
                let assert model.RemoteSource(req, r, _old) = s
                model.RemoteSource(req, r, table)
              })
            let state = Model(sections, mode)
            #(state, effect.none())
          }),
        )
      })
      // should I trigger promise from in here or not
      Nil
    }),
  )
}

fn subsection(index, mode) {
  case mode {
    model.SouceSelection(i, raw) if i == index ->
      div([class("border cover")], [
        form(
          [
            event.on("submit", fn(e) {
              event.prevent_default(e)
              Ok(model.Wrap(submit_remote))
            }),
          ],
          [
            input([
              class("border"),
              attribute.value(dynamic.from(raw)),
              on_input(fn(new) {
                model.Wrap(fn(state) {
                  let Model(sections, mode) = state
                  let assert model.SouceSelection(i, _old) = mode
                  let mode = model.SouceSelection(i, new)
                  #(Model(sections, mode), effect.none())
                })
              }),
            ]),
            button([class("bg-red-500 p-2"), attribute.type_("submit")], [
              text("fetch source"),
            ]),
          ],
        ),
        text("source selection"),
      ])
    _ ->
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
        button(
          [
            class("cursor bg-green-300 rounded"),
            on_click(model.Wrap(fetch_source(_, index))),
          ],
          [text("add source")],
        ),
      ])
  }
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

fn fetch_source(model, index) {
  let mode = model.SouceSelection(index, "")
  #(Model(..model, mode: mode), effect.none())
}
