import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import gleroglero/outline
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import mysig/route
import website/components
import website/components/clock
import website/routes/common
import website/routes/news/appearance
import website/routes/news/archive
import website/routes/news/edition.{Edition}

pub fn route() {
  let items = web_editions(archive.published)

  route.Route(index: route.Page(home_page()), items: [
    #(
      "editions",
      route.Route(index: route.Page(asset.done("no page here")), items: items),
    ),
  ])
}

fn render_edition(edition, index) {
  let Edition(title:, date:, ..) = edition
  let content = [
    h.div([a.class("font-bold")], [
      element.text("News: #"),
      element.text(int.to_string(index)),
    ]),
    h.div([], [
      h.a(
        [
          a.class("underline"),
          a.href("/news/editions/" <> int.to_string(index)),
        ],
        [element.text(title)],
      ),
    ]),
  ]
  #(outline.newspaper(), content, date)
}

fn render_appearance(appearance) {
  case appearance {
    appearance.Podcast(series:, episode:, link:, aired:) -> {
      let content = [
        h.div([a.class("font-bold")], [
          element.text("Podcast: "),
          element.text(series),
        ]),
        h.div([], [
          h.a([a.class("underline"), a.href(link)], [element.text(episode)]),
        ]),
      ]
      #(outline.radio(), content, clock.date_to_string(aired))
    }
    appearance.Meetup(name:, title:, video:, date:) -> {
      let content = [
        h.div([a.class("font-bold")], [
          element.text("Meetup: "),
          element.text(name),
        ]),
        h.a([a.class("underline"), a.href(video)], [element.text(title)]),
      ]
      #(outline.video_camera(), content, clock.date_to_string(date))
    }
    appearance.Conference(name:, title:, lightning:, video:, date:) -> {
      let content = [
        h.div([a.class("font-bold")], [
          element.text("Conference: "),
          element.text(name),
        ]),
        h.a([a.class("underline"), a.href(video)], [element.text(title)]),
      ]
      let icon = case lightning {
        True -> outline.bolt()
        False -> outline.presentation_chart_line()
      }
      #(icon, content, clock.date_to_string(date))
    }
  }
}

pub fn home_page() {
  let assert [latest, ..rest] = archive.published
  let index = list.length(archive.published)

  let log =
    list.flatten([
      list.index_map(rest, fn(edition, i) {
        render_edition(edition, index - 1 - i)
      }),
      list.map(appearance.apperances(), render_appearance),
    ])
    |> list.sort(fn(a, b) {
      let #(_, _, a) = a
      let #(_, _, b) = b

      string.compare(b, a)
    })
    |> list.map(fn(item) {
      let #(icon, content, date) = item
      h.div([a.class("max-w-3xl mx-auto")], [
        h.div([a.class("flex p-2 gap-2")], [
          h.div([a.class("w-9 font-gray-800")], [icon]),
          h.div(
            [],
            list.append(content, [
              h.div([a.class("mt-2 text-gray-600")], [
                h.time([a.attribute("datetime", date)], [element.text(date)]),
              ]),
            ]),
          ),
        ]),
      ])
    })

  use pea <- asset.do(asset.load("src/website/images/pea.webp"))
  use layout <- asset.do(asset.load("src/website/routes/layout.css"))
  let page =
    html.doc(
      list.flatten([
        [
          html.stylesheet(html.tailwind_2_2_11),
          html.stylesheet(asset.src(layout)),
          h.meta([a.name("twitter:card"), a.content("summary_large_image")]),
        ],
        common.page_meta(
          "/news",
          "EYG news",
          "Updates from the development of the EYG language and structural editor.",
        ),
        common.diagnostics(),
      ]),
      [
        components.header(fn(_) { todo }, None),
        h.div([a.class("pt-14 pb-1 p-2")], [
          h.div([a.class("max-w-3xl mx-auto")], [
            h.h1([a.class("text-xl font-bold")], [element.text("News")]),
            h.p([], [
              element.text(
                "What's happening with EYG? See the latest edition of our newsletter.",
              ),
            ]),
          ]),
          h.div(
            [
              a.style([#("max-width", "660px")]),
              a.class(
                "mx-auto my-4 rounded-xl border-black border overflow-hidden",
              ),
            ],
            [
              letter_container([edition.preview(latest, index, asset.src(pea))]),
              h.div([a.style([#("padding", "0 1.5rem")])], [
                h.a(
                  [
                    a.class("underline"),
                    a.href("/news/editions/" <> int.to_string(index)),
                  ],
                  [element.text("Read the full issue.")],
                ),
              ]),
            ],
          ),
          components.signup_inline(),
          h.div([a.class("max-w-3xl mx-auto")], [
            h.h2([a.class("text-xl font-bold")], [element.text("Previously")]),
          ]),
          ..log
        ]),
        components.footer(),
      ],
    )
  asset.done(element.to_document_string(page))
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
            ],
            common.page_meta(
              "/news/editions/" <> int.to_string(index),
              "EYG news: " <> title,
              "Updates from the development of the EYG language and structural editor.",
            ),
            common.diagnostics(),
          ]),
          [
            h.div(
              [a.id("container"), a.style([#("background", edition.charcoal)])],
              [letter_container([edition]), inline_subscribe()],
            ),
          ],
        )
      asset.done(element.to_document_string(page))
    }
    #(int.to_string(index), route.Route(index: route.Page(page), items: []))
  })
}

fn letter_container(contents) {
  h.div(
    [
      a.style([
        #("margin", "0 auto"),
        #("max-width", "660px"),
        #("background", "white"),
      ]),
    ],
    contents,
  )
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
