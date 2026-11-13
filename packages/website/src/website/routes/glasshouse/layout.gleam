//// The shell shared by the Glasshouse pages, in the style of the rest of the site.

import gleam/list
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import mysig/asset
import mysig/html
import website/routes/common
import website/routes/home

pub const stylesheet = "src/website/routes/glasshouse/glasshouse.css"

/// Links between the Glasshouse pages, the active page is marked.
pub fn nav(active: String) -> Element(msg) {
  let link = fn(href, text) {
    h.a(
      [
        a.href(href),
        a.class("gh-nav-link"),
        a.classes([#("gh-nav-active", href == active)]),
      ],
      [element.text(text)],
    )
  }
  h.nav([a.class("gh-nav")], [
    h.div([a.class("gh-nav-inner")], [
      h.a([a.href("/glasshouse"), a.class("gh-brand")], [
        element.text("Glasshouse"),
      ]),
      link("/glasshouse", "Overview"),
      link("/glasshouse/documentation", "Documentation"),
      link("/glasshouse/runtime-acquisition.html", "Runtime acquisition"),
      link("/glasshouse/debugger", "Debugger"),
      link("/guides/trajectories", "CLI guide"),
    ]),
  ])
}

/// A full page with the site's styles, the Glasshouse styles and page metadata.
pub fn page(path, title, description, head, body) {
  use layout <- asset.do(asset.load(home.layout_path))
  use neo <- asset.do(asset.load("src/website/routes/neo.css"))
  use glasshouse <- asset.do(asset.load(stylesheet))
  html.doc(
    list.flatten([
      [
        html.stylesheet(html.tailwind_2_2_11),
        html.stylesheet(asset.src(layout)),
        html.stylesheet(asset.src(neo)),
        html.stylesheet(asset.src(glasshouse)),
      ],
      head,
      common.page_meta(path, title, description),
      common.diagnostics(),
    ]),
    body,
  )
  |> asset.done()
}
