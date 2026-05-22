import gleam/list
import gleam/result
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mork
import mysig/asset
import mysig/html
import mysig/route as route_builder
import simplifile
import website/components
import website/components/markdown
import website/routes/common
import website/routes/home

pub type Guide {
  Guide(slug: String, name: String, description: String, content: String)
}

fn get_field(lines, key) {
  list.find_map(lines, fn(line) {
    case string.split_once(line, ":") {
      Ok(#(k, value)) if k == key -> Ok(string.trim(value))
      _ -> Error(Nil)
    }
  })
}

fn all(root) -> List(Guide) {
  let assert Ok(paths) = simplifile.get_files(root)
  list.filter_map(paths, fn(path) {
    let assert Ok(raw) = simplifile.read(path)

    let #(front, content) = mork.split_frontmatter_from_input(raw)
    let lines = string.split(front, "\n")
    use name <- result.try(get_field(lines, "name"))
    use description <- result.try(get_field(lines, "description"))
    let slug =
      get_field(lines, "slug")
      |> result.unwrap(
        name
        |> string.replace(" ", "-")
        |> string.replace("_", "-")
        |> string.lowercase
        |> string.trim,
      )

    Ok(Guide(slug:, name:, description:, content:))
  })
}

pub fn from_repo() {
  all("../../guides")
}

pub fn route() {
  route_builder.Route(
    index: route_builder.Page(index_page()),
    items: list.flat_map(from_repo(), fn(guide) {
      let Guide(slug:, ..) = guide
      [
        #(
          slug,
          route_builder.Route(
            index: route_builder.Page(guide_page(guide)),
            items: [],
          ),
        ),
        #(
          slug <> ".md",
          route_builder.Route(
            index: route_builder.Static(<<guide.content:utf8>>),
            items: [],
          ),
        ),
      ]
    }),
  )
}

fn layout(path, title, description, body) {
  use layout <- asset.do(asset.load(home.layout_path))
  use neo <- asset.do(asset.load("src/website/routes/neo.css"))
  html.doc(
    list.flatten([
      [
        html.stylesheet(html.tailwind_2_2_11),
        html.stylesheet(asset.src(layout)),
        html.stylesheet(asset.src(neo)),
        common.prism_style(),
      ],
      common.page_meta(path, title, description),
      common.diagnostics(),
    ]),
    body,
  )
  |> asset.done()
}

fn index_body() {
  [
    components.header(),
    h.main([a.class("mx-auto w-full max-w-5xl px-4 pt-20 pb-16")], [
      h.h1([a.class("text-4xl font-bold leading-tight")], [
        element.text("Guides"),
      ]),
      h.p([a.class("mt-3 max-w-2xl text-lg leading-7 text-gray-700")], [
        element.text(
          "Static references for installing EYG, writing programs, using effects, and embedding the runtime.",
        ),
      ]),
      h.div(
        [a.class("mt-8 grid gap-4 md:grid-cols-2")],
        list.map(from_repo(), card),
      ),
    ]),
    components.footer(),
  ]
}

fn card(guide) {
  let Guide(slug:, name:, description:, ..) = guide
  h.a(
    [
      a.href("/guides/" <> slug),
      a.class(
        "block border-2 border-black bg-white p-4 shadow-md hover:bg-green-100",
      ),
    ],
    [
      h.h2([a.class("text-xl font-bold")], [element.text(name)]),
      h.p([a.class("mt-2 leading-6 text-gray-700")], [element.text(description)]),
    ],
  )
}

pub fn index_page() {
  use content <- asset.do(layout(
    "/guides",
    "EYG guides",
    "Guides for installing, writing and embedding EYG.",
    index_body(),
  ))
  asset.done(element.to_document_string(content))
}

fn guide_body(guide) {
  let Guide(content:, ..) = guide

  [
    components.header(),
    h.main([a.class("mx-auto w-full max-w-4xl px-4 pt-20 pb-16")], [
      h.a([a.href("/guides"), a.class("font-bold underline")], [
        element.text("Guides"),
      ]),
      h.article([a.class("mt-4")], markdown.render(content)),
    ]),
    components.footer(),
  ]
}

pub fn guide_page(guide: Guide) {
  let Guide(slug:, name:, description:, ..) = guide
  use content <- asset.do(layout(
    "/guides/" <> slug,
    name,
    description,
    guide_body(guide),
  ))
  asset.done(element.to_document_string(content))
}
