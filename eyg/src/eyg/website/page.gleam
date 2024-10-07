import gleam/bit_array
import gleam/list
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import midas/task as t
import mysig
import mysig/layout
import mysig/neo

pub fn app(module, func, bundle) {
  use script <- t.do(t.bundle(module, func))
  t.done(layout(
    "app",
    [empty_lustre(), mysig.resource(mysig.js("page", script), bundle)],
    bundle,
  ))
}

fn layout(name, body, bundle) {
  doc(
    "EYG - " <> name,
    "eyg.run",
    [
      stylesheet(mysig.tailwind_2_2_11),
      mysig.resource(layout.css, bundle),
      mysig.resource(neo.css, bundle),
    ],
    body,
  )
  |> element.to_document_string()
  |> bit_array.from_string()
}

pub fn doc(title, domain, head, body) {
  h.html([a.attribute("lang", "en")], [
    h.head([], list.append(common_head_tags(title, domain), head)),
    h.body([], body),
  ])
}

fn common_head_tags(title, domain) {
  [
    h.meta([a.attribute("charset", "UTF-8")]),
    h.meta([
      a.attribute("http-equiv", "X-UA-Compatible"),
      a.attribute("content", "IE=edge"),
    ]),
    h.meta([a.attribute("viewport", "width=device-width, initial-scale=1.0")]),
    h.title([], title),
    h.script(
      [
        a.attribute("defer", ""),
        a.attribute("data-domain", domain),
        a.src("https://plausible.io/js/script.js"),
      ],
      "",
    ),
  ]
}

fn stylesheet(reference) {
  h.link([a.rel("stylesheet"), a.href(reference)])
}

fn empty_lustre() {
  h.div([a.id("app")], [])
}
