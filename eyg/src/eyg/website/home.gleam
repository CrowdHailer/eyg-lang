import drafting/state
import drafting/view/page
import eyg/website/utils
import eygir/decode
import eygir/encode
import eygir/expression as e
import gleam/bit_array
import gleam/io
import gleam/javascript/array
import gleam/list
import gleam/string
import lustre
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import midas/task as t
import morph/editable
import morph/lustre/frame
import morph/lustre/render
import plinth/browser/document
import plinth/browser/element as plinth_element

pub fn build() {
  use client <- t.do(t.bundle("eyg/website/home", "client"))
  let client = #("/home.js", <<client:utf8>>)
  let bits =
    page(client)
    |> element.to_document_string
    |> bit_array.from_string

  t.done([#("/index.html", bits), client])
}

pub fn page(client) {
  h.html([], [
    h.head([], [
      h.meta([a.attribute("charset", "UTF-8")]),
      h.meta([
        a.name("viewport"),
        a.attribute("content", "width=device-width, initial-scale=1.0"),
      ]),
      h.title([], "EYG"),
      h.meta([
        a.name("description"),
        a.attribute(
          "content",
          "Updates from the development of the EYG language and editor.",
        ),
      ]),
      utils.tailwind(),
      utils.layout_css(),
      h.link([a.rel("shortcut icon"), a.href("/assets/pea.webp")]),
      utils.plausible("eyg.run"),
    ]),
    h.body([a.class("vstack"), a.style([])], [
      h.div([], [element.text("next")]),
      example(e.Vacant("hello")),
      utils.js(client),
    ]),
  ])
}

pub fn client() {
  document.query_selector_all("[data-eyg=editor]")
  |> array.to_list
  |> list.each(start_editor)
}

fn start_editor(target) {
  let source =
    plinth_element.inner_text(target)
    |> decode.from_json
  case source {
    Ok(source) -> {
      let assert Ok(element) =
        render.expression(editable.from_expression(source))
        |> frame.to_fat_line
        |> element.to_string()
        |> string.append("<div id=\"a\">foii</div>")
        // |> plinth_element.set_inner_text(target, _)
        |> plinth_element.insert_adjacent_html(
          target,
          plinth_element.AfterEnd,
          _,
        )
      // todo as "I need a ref to start the app"
      io.debug(element)
      let app = lustre.application(state.init, state.update, page.render)
      lustre.start(app, "#a", Nil)
    }
    Error(_) -> {
      plinth_element.insert_adjacent_html(
        target,
        plinth_element.AfterEnd,
        "bad content",
      )
      todo
    }
  }
}

fn update(state, mesasge) {
  state
}

fn render(state) {
  element.text("hello lustre")
}

// @external(javascript, "../../../../lustre/client-runtime.ffi.mjs", "start")
// fn start(
//   _app: lustre.App(flags, model, msg),
//   _element: plinth_element.Element,
//   _flags: flags,
// ) -> Result(fn(lustre.Action(msg, lustre.ClientSpa)) -> Nil, lustre.Error)

pub fn example(source) {
  h.script(
    [a.type_("application/json"), a.attribute("data-eyg", "editor")],
    encode.to_json(source),
  )
}
