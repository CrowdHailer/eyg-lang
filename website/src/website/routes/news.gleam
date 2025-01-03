import gleam/int
import gleam/list
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import mysig/route
import website/routes/common
import website/routes/news/archive
import website/routes/news/edition.{Edition}

pub fn route() {
  let items = web_editions(archive.published)
  route.Route(index: route.Page(asset.done("no page here")), items: [
    #(
      "editions",
      route.Route(index: route.Page(asset.done("no page here")), items: items),
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
        html.doc(
          list.flatten([
            [
              html.stylesheet(asset.src(layout)),
              h.style(
                [],
                "
              #container {
                padding: 0px;
              }
              #container > div {
                padding: 4px;
              }
              @media (min-width: 640px) {
                #container {
                  padding: 12px
                }
                #container > div {
                  padding: 12px;
                  border-radius: 12px;
                }
              }",
              ),
              h.meta([a.name("twitter:card"), a.content("summary_large_image")]),
              html.plausible("eyg.run"),
            ],
            common.page_meta(
              "/news/editions/" <> int.to_string(index),
              "EYG news: " <> title,
              "Updates from the development of the EYG language and structural editor.",
            ),
          ]),
          [
            h.div(
              [
                a.id("container"),
                a.style([
                  // #("margin", "12px auto"),
                  // #("max-width", "660px"),
                  #("background", edition.charcoal),
                  // #("padding", "12px"),
                // #("border-radius", "12px"),
                ]),
              ],
              [
                // inline_subscribe(),
                h.div(
                  [
                    a.style([
                      #("margin", "0 auto"),
                      #("max-width", "660px"),
                      #("background", "white"),
                    ]),
                  ],
                  [edition],
                ),
                inline_subscribe(),
              ],
            ),
          ],
        )
      asset.done(element.to_document_string(page))
    }

    #(int.to_string(index), route.Route(index: route.Page(page), items: []))
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
