import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import midas/task as t
import mysig/asset
import mysig/html
import mysig/layout
import mysig/route
import snag
import website/routes/news/archive
import website/routes/news/edition.{Edition}

const replace_string = "!CONTENT!"

pub fn route(bundle) {
  use pea <- t.do(t.read("/src/website/images/pea.webp"))
  use pea <- t.do(asset.webp("pea", pea))
  use template <- t.do(t.read("/src/website/routes/news/edition/email.html"))
  use template <- t.try(
    bit_array.to_string(template)
    |> result.replace_error(snag.new("not a utf8 string")),
  )
  let assert [latest, ..] = archive.published
  let pea_src = asset.path(pea, bundle)
  let content =
    element.to_string(edition.render(
      latest,
      list.length(archive.published),
      pea_src,
    ))
  let template = string.replace(template, replace_string, content)

  use layout <- t.do(layout.css())
  let layout = asset.resource(layout, bundle)

  let items = [
    #("_email.html", route.Route(index: route.Page(template), items: [])),
    ..web_editions(archive.published, pea, bundle, layout)
  ]
  // use pea 
  route.Route(index: route.Page("Nope or put in a Some"), items: items)
  |> t.done()
}

// archive is a reverse order stack of editions
fn web_editions(editions, pea, bundle, layout) {
  let pea_src = asset.path(pea, bundle)
  list.index_map(list.reverse(editions), fn(edition, index) {
    let index = index + 1
    let Edition(title: title, ..) = edition
    let edition = edition.render(edition, index, pea_src)

    let path = "/editions/" <> int.to_string(index)
    let page =
      h.html([], [
        h.head([], [
          h.meta([a.attribute("charset", "UTF-8")]),
          h.meta([
            a.name("viewport"),
            a.attribute("content", "width=device-width, initial-scale=1.0"),
          ]),
          h.title([], "EYG news: " <> title),
          h.meta([
            a.name("description"),
            a.attribute(
              "content",
              "Updates from the development of the EYG language and editor.",
            ),
          ]),
          layout,
          h.link([a.rel("shortcut icon"), a.href(pea_src)]),
          html.plausible("eyg.run"),
        ]),
        h.body(
          [
            a.class("vstack"),
            a.style([
              // #("margin", "12px auto"),
              // #("max-width", "660px"),
              #("background", edition.charcoal),
              // #("padding", "12px"),
              #("border-radius", "12px"),
            ]),
          ],
          [
            // inline_subscribe(),
            h.div(
              [
                a.style([
                  #("margin", "12px auto"),
                  #("max-width", "660px"),
                  #("background", "white"),
                  #("padding", "12px"),
                  #("border-radius", "12px"),
                ]),
              ],
              [edition],
            ),
            inline_subscribe(),
          ],
        ),
      ])
      |> element.to_document_string
    #(path, route.Route(index: route.Page(page), items: []))
  })
}

fn inline_subscribe() {
  h.div(
    [
      a.style([
        #("margin", "0 auto"),
        #("width", "600px"),
        #("background", "white"),
      ]),
    ],
    [
      h.script(
        [
          a.src(
            "https://eocampaign1.com/form/b3a478b8-39e2-11ef-97b9-955caf3f5f36.js",
          ),
          a.attribute("async", ""),
          a.attribute("data-form", "b3a478b8-39e2-11ef-97b9-955caf3f5f36"),
        ],
        "",
      ),
    ],
  )
}
