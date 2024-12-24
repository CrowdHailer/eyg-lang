import gleam/int
import gleam/list
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import mysig/route
import website/routes/news/archive
import website/routes/news/edition.{Edition}

pub fn route() {
  let items = web_editions(archive.published)
  route.Route(index: asset.done(element.text("no page here")), items: [
    #(
      "editions",
      route.Route(index: asset.done(element.text("no page here")), items: items),
    ),
  ])
}

// archive is a reverse order stack of editions
fn web_editions(editions) {
  list.index_map(list.reverse(editions), fn(edition, index) {
    let index = index + 1
    let Edition(title: title, ..) = edition
    let page = {
      use pea <- asset.do(asset.load("src/website/images/pea.webp"))
      use layout <- asset.do(asset.load("src/website/routes/layout.css"))
      let edition = edition.render(edition, index, asset.src(pea))

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
            html.stylesheet(asset.src(layout)),
            h.link([a.rel("shortcut icon"), a.href(asset.src(pea))]),
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
      asset.done(page)
    }

    #(int.to_string(index), route.Route(index: page, items: []))
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
