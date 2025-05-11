import gleam/dict
import gleam/int
import gleam/list
import jot
import lustre/attribute as a
import lustre/element as e
import lustre/element/html as h

pub const white = "#fefefc"

const unexpected_aubergine = "#584355"

const mint_green = "#e7ffdd"

pub const charcoal = "#2f2f2f"

const blacker = "#151515"

pub type Edition {
  Edition(date: String, title: String, content: String)
}

fn main(sections) {
  h.div([a.style([#("padding", "1.5rem 1.5rem 0rem 1.5rem")])], sections)
}

pub fn header(issue_url, number, pea_src) {
  h.div([a.style([#("padding", ".5rem 1.5rem"), #("background", mint_green)])], [
    h.table(
      [
        a.attribute("width", "100%"),
        a.attribute("border", "0"),
        a.attribute("cellpadding", "0"),
        a.attribute("cellspacing", "0"),
      ],
      [
        h.tbody([], [
          h.tr([], [
            h.td([a.style([#("vertical-align", "text-bottom")])], [
              h.img([
                a.class("inline-block"),
                a.alt("Penelopea, EYG's mascot"),
                a.src(pea_src),
                a.width(80),
                a.height(64),
                a.style([
                  #("width", "64px"),
                  #("height", "64px"),
                  #("vertical-align", "bottom"),
                  #("margin-bottom", "-10px"),
                  // #("margin-top", "-10px"),
                ]),
              ]),
              h.span(
                [
                  a.style([
                    #("font-size", "1.5rem"),
                    #("color", blacker),
                    #("font-weight", "bold"),
                  ]),
                ],
                [
                  h.a(
                    [
                      a.href("https://eyg.run/"),
                      a.style([
                        #("text-decoration", "none"),
                        #("color", blacker),
                      ]),
                    ],
                    [e.text("EYG news")],
                  ),
                ],
              ),
              h.span([a.style([#("color", unexpected_aubergine)])], [
                e.text(" from "),
                h.a(
                  [
                    a.style([#("text-decoration", "none"), #("color", blacker)]),
                    a.href("https://twitter.com/crowdhailer"),
                  ],
                  [e.text("@Crowdhailer")],
                ),
              ]),
            ]),
            h.td(
              [
                a.style([
                  #("text-align", "right"),
                  #("vertical-align", "text-bottom"),
                ]),
                a.attribute("align", "right"),
              ],
              [
                h.a(
                  [
                    a.href(issue_url),
                    a.style([
                      #("font-size", "1.5rem"),
                      #("text-decoration", "none"),
                      #("color", blacker),
                    ]),
                  ],
                  [e.text("Issue #"), e.text(int.to_string(number))],
                ),
              ],
            ),
          ]),
        ]),
      ],
    ),
  ])
}

fn footer(edition_url) {
  h.div([a.style([#("background", mint_green), #("padding", ".5rem 1.5rem")])], [
    block(
      jot.Paragraph(dict.new(), [
        jot.Text("That's all for this update, I hope you have enjoyed it."),
      ]),
    ),
    block(
      jot.Paragraph(dict.new(), [
        jot.Text("This issue is available, and shareable, at "),
        jot.Link([jot.Text(edition_url)], jot.Url(edition_url)),
      ]),
    ),
  ])
}

pub fn preview(post, index, pea_src) {
  let Edition(_date, title, raw) = post
  let document = jot.parse(raw)
  let jot.Document(content, _references, _footnotes) = document
  let sections =
    list.map(
      [jot.Heading(dict.new(), 1, [jot.Text(title)]), ..list.take(content, 1)],
      block,
    )
  let edition_url = "https://eyg.run/news/editions/" <> int.to_string(index)
  h.div(
    [
      a.style([
        // #("font-family", "Helvetica, Arial, sans-serif"),

        #(
          "font-family",
          "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol'",
        ),
        #("line-height", "1.5"),
      ]),
    ],
    [header(edition_url, index, pea_src), main(sections)],
  )
}

pub fn render(post, index, pea_src) {
  let Edition(_date, title, raw) = post
  let document = jot.parse(raw)
  let jot.Document(content, _references, _footnotes) = document
  let sections =
    list.map([jot.Heading(dict.new(), 1, [jot.Text(title)]), ..content], block)
  let edition_url = "https://eyg.run/news/editions/" <> int.to_string(index)
  h.div(
    [
      a.style([
        // #("font-family", "Helvetica, Arial, sans-serif"),

        #(
          "font-family",
          "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol'",
        ),
        #("line-height", "1.5"),
      ]),
    ],
    [header(edition_url, index, pea_src), main(sections), footer(edition_url)],
  )
}

fn p(children) {
  h.p(
    [a.style([#("margin-top", "20px"), #("margin-bottom", "20px")])],
    children,
  )
}

fn h1(children) {
  h.h1(
    [
      a.style([
        #("margin-top", "20px"),
        #("margin-bottom", "20px"),
        #("line-height", "1"),
        #("font-size", "1.75rem"),
      ]),
    ],
    children,
  )
}

fn h2(children) {
  h.h2(
    [a.style([#("margin-top", "20px"), #("margin-bottom", "20px")])],
    children,
  )
}

fn h3(children) {
  h.h3(
    [a.style([#("margin-top", "20px"), #("margin-bottom", "20px")])],
    children,
  )
}

pub fn block(container) {
  case container {
    jot.Paragraph(_attributes, content) -> p(inline(content))
    jot.Heading(_attributes, 1, content) -> h1(inline(content))
    jot.Heading(_attributes, 2, content) -> h2(inline(content))
    jot.Heading(_attributes, 3, content) -> h3(inline(content))
    jot.Heading(_attributes, _level, _content) ->
      panic as "only h1,h2,h3 are supported"
    jot.ThematicBreak -> panic as "thematic break not supported"
    jot.Codeblock(_attributes, _language, content) ->
      h.pre(
        [
          a.style([
            #("color", "#e2e8f0"),
            #("background-color", "#2d3748"),
            #("overflow-x", "auto"),
            #("font-size", "14px"),
            #("line-height", "1.7142857"),
            #("margin-top", "27px"),
            #("margin-bottom", "27px"),
            #("border-radius", "6px"),
            #("padding-top", "13px"),
            #("padding-right", "18px"),
            #("padding-bottom", "13px"),
            #("padding-left", "18px"),
          ]),
        ],
        [
          h.code(
            [
              a.style([
                #("background-color", "transparent"),
                #("border-width", "0"),
                #("border-radius", "0"),
                #("padding", "0"),
                #("font-weight", "400"),
                #("color", "inherit"),
                #("font-size", "inherit"),
                #("font-family", "inherit"),
                #("line-height", "inherit"),
              ]),
            ],
            [e.text(content)],
          ),
        ],
      )
    jot.RawBlock(_content) -> panic as "not supported"
  }
}

pub fn inline(content) {
  list.map(content, fn(item) {
    case item {
      jot.Linebreak -> h.br([])
      jot.Text(content) -> e.text(content)
      jot.Link(content, destination) ->
        h.a(
          [
            a.style([#("text-decoration", "underline")]),
            {
              let assert jot.Url(url) = destination
              a.href(url)
            },
          ],
          inline(content),
        )
      jot.Image(_content, destination) ->
        h.img([
          {
            let assert jot.Url(url) = destination
            a.src(url)
          },
          a.style([#("max-width", "100%")]),
          // a.alt(content),
        ])
      jot.Emphasis(content) -> h.em([], inline(content))
      jot.Strong(content) -> h.strong([], inline(content))
      jot.Code(content) ->
        h.code(
          [
            a.style([
              #("color", "#e2e8f0"),
              #("background-color", "#2d3748"),
              #("font-size", "14px"),
              #("border-radius", "4px"),
              #("padding-top", "1px"),
              #("padding-right", "3px"),
              #("padding-bottom", "1px"),
              #("padding-left", "3px"),
            ]),
          ],
          [e.text(content)],
        )
      jot.Footnote(_) -> todo
    }
  })
}
