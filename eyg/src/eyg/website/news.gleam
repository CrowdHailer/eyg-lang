import eyg/website/news/archive
import eyg/website/news/edition.{Edition}
import eyg/website/utils
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import midas/task as t
import snag

const replace_string = "!CONTENT!"

pub fn build() {
  use layout <- t.do(t.read("layout2.css"))
  let layout = #("/assets/layout.css", layout)
  use pea <- t.do(t.read("src/eyg/website/news/pea.webp"))
  let pea = #("/assets/pea.webp", pea)
  use brocolli <- t.do(t.read("src/eyg/website/news/brocolli.webp"))
  let brocolli = #("/assets/brocolli.webp", brocolli)

  use template <- t.do(t.read("src/eyg/website/news/edition/email.html"))
  use template <- t.try(
    bit_array.to_string(template)
    |> result.replace_error(snag.new("not a utf8 string")),
  )
  let assert [latest, ..] = archive.published
  let content =
    element.to_string(edition.render(latest, list.length(archive.published)))
  let template = string.replace(template, replace_string, content)

  t.done([
    #("/news/_email.html", <<template:utf8>>),
    layout,
    pea,
    brocolli,
    ..web_editions(archive.published, layout)
  ])
}

// archive is a reverse order stack of editions
fn web_editions(editions, layout) {
  list.index_map(list.reverse(editions), fn(edition, index) {
    let index = index + 1
    let Edition(title: title, ..) = edition
    let edition = edition.render(edition, index)

    let path = "/news/editions/" <> int.to_string(index) <> "/index.html"
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
          utils.css(layout),
          h.link([a.rel("shortcut icon"), a.href("/assets/pea.webp")]),
          h.script(
            [
              a.attribute("defer", ""),
              a.attribute("data-domain", "eyg.run"),
              a.src("https://plausible.io/js/script.js"),
            ],
            "",
          ),
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
      |> bit_array.from_string
    #(path, page)
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
