import gleam/list
import gleam/option.{None, Some}
import gleam/string
import jot
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import website/components/code_block

pub fn render(content: String) -> List(element.Element(msg)) {
  content
  |> string.split("\n")
  |> collect([])
}

fn collect(
  lines: List(String),
  markdown: List(String),
) -> List(element.Element(msg)) {
  case lines {
    [] -> flush_markdown(markdown)
    [line, next, ..rest] ->
      case is_table_start(line, next) {
        True -> {
          let #(table_lines, rest) = take_table_rows([line, next, ..rest], [])
          list.append(flush_markdown(markdown), [
            table(table_lines),
            ..collect(rest, [])
          ])
        }
        False -> collect([next, ..rest], [line, ..markdown])
      }
    [line, ..rest] -> collect(rest, [line, ..markdown])
  }
}

fn flush_markdown(lines: List(String)) {
  case lines {
    [] -> []
    lines -> {
      let jot.Document(content:, ..) =
        lines
        |> list.reverse
        |> string.join("\n")
        |> jot.parse

      list.map(content, block)
    }
  }
}

fn block(container) {
  case container {
    jot.Paragraph(_attributes, content) -> p(inline(content))
    jot.Heading(_attributes, level, content) ->
      heading(level, inline_text(content), inline(content))
    jot.Codeblock(_attributes, language, content) ->
      code_block.render(option_string(language), content)
    jot.BulletList(items:, ..) ->
      h.ul(
        [a.class("my-4 list-disc pl-6")],
        list.map(items, fn(item) { h.li([], list.map(item, block)) }),
      )
    jot.BlockQuote(items:, ..) ->
      h.blockquote(
        [a.class("my-4 border-l-4 border-gray-300 pl-4 text-gray-700")],
        list.map(items, block),
      )
    jot.Div(items:, ..) -> h.div([], list.map(items, block))
    jot.RawBlock(content) -> h.pre([], [element.text(content)])
    jot.ThematicBreak -> h.hr([a.class("my-8")])
    jot.OrderedList(..) -> panic as "switch to pamphlet"
  }
}

fn p(children) {
  h.p([a.class("my-4 leading-7")], children)
}

fn heading(level: Int, id: String, children) {
  let attrs = [
    a.id(slug(id)),
    a.class("font-bold leading-tight mt-10 mb-4 scroll-mt-16"),
  ]

  case level {
    1 -> h.h1([a.class("text-4xl mb-6 leading-tight")], children)
    2 -> h.h2(list.append(attrs, [a.class("text-3xl")]), children)
    3 -> h.h3(list.append(attrs, [a.class("text-2xl")]), children)
    4 -> h.h4(list.append(attrs, [a.class("text-xl")]), children)
    5 -> h.h5(list.append(attrs, [a.class("text-lg")]), children)
    _ -> h.h6(list.append(attrs, [a.class("text-base")]), children)
  }
}

// TODO switch to pamphlet
fn inline(content) {
  list.map(content, fn(item) {
    case item {
      jot.Linebreak -> h.br([])
      jot.NonBreakingSpace -> element.text(" ")
      jot.Text(content) -> element.text(content)
      jot.Link(content:, destination:, ..) ->
        h.a(
          [a.class("underline"), a.href(destination_url(destination))],
          inline(content),
        )
      jot.Image(content:, destination:, ..) ->
        h.img([
          a.src(destination_url(destination)),
          a.alt(inline_text(content)),
          a.class("max-w-full"),
        ])
      jot.Span(content:, ..) -> h.span([], inline(content))
      jot.Emphasis(content) -> h.em([], inline(content))
      jot.Strong(content) -> h.strong([], inline(content))
      jot.Code(content) -> inline_code(content)
      jot.MathInline(content) | jot.MathDisplay(content) -> inline_code(content)
      jot.Footnote(reference) -> h.sup([], [element.text(reference)])
      jot.Delete(content: _) -> panic as "switch to pamphlet"
      jot.Insert(content: _) -> panic as "switch to pamphlet"
      jot.Mark(content: _) -> panic as "switch to pamphlet"
      jot.Superscript(content: _) -> panic as "switch to pamphlet"
      jot.Subscript(content: _) -> panic as "switch to pamphlet"
      jot.Symbol(content: _) -> panic as "switch to pamphlet"
    }
  })
}

fn inline_code(content) {
  h.code(
    [
      a.styles([
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
    [element.text(content)],
  )
}

fn destination_url(destination) {
  case destination {
    jot.Url(url) -> url
    jot.Reference(name) -> "#" <> name
  }
}

fn option_string(option) {
  case option {
    Some(value) -> value
    None -> ""
  }
}

fn is_table_start(line: String, next: String) {
  is_table_row(line) && is_separator_row(next)
}

fn is_table_row(line: String) {
  string.trim(line)
  |> string.starts_with("|")
}

fn is_separator_row(line: String) {
  case is_table_row(line) {
    False -> False
    True ->
      line
      |> table_cells
      |> list.all(fn(cell) {
        let cell = string.trim(cell)
        cell != ""
        && cell
        |> string.to_graphemes
        |> list.all(fn(char) { char == "-" || char == ":" })
      })
  }
}

fn take_table_rows(lines: List(String), acc: List(String)) {
  case lines {
    [line, ..rest] ->
      case is_table_row(line) {
        True -> take_table_rows(rest, [line, ..acc])
        False -> #(list.reverse(acc), [line, ..rest])
      }
    rest -> #(list.reverse(acc), rest)
  }
}

fn table(lines: List(String)) {
  let assert [head, _separator, ..rows] = lines
  h.div([a.class("my-6 overflow-x-auto")], [
    h.table([a.class("w-full border-collapse text-left text-sm")], [
      h.thead([], [
        h.tr(
          [],
          list.map(table_cells(head), fn(cell) {
            h.th(
              [a.class("border border-gray-300 bg-gray-100 px-3 py-2")],
              cell_inline(cell),
            )
          }),
        ),
      ]),
      h.tbody(
        [],
        list.map(rows, fn(row) {
          h.tr(
            [],
            list.map(table_cells(row), fn(cell) {
              h.td(
                [a.class("border border-gray-300 px-3 py-2 align-top")],
                cell_inline(cell),
              )
            }),
          )
        }),
      ),
    ]),
  ])
}

fn table_cells(line: String) {
  let line = string.trim(line)
  let line = case string.starts_with(line, "|") {
    True -> string.drop_start(line, 1)
    False -> line
  }
  let line = case string.ends_with(line, "|") {
    True -> string.drop_end(line, 1)
    False -> line
  }

  string.split(line, "|")
  |> list.map(string.trim)
}

fn cell_inline(cell: String) {
  let jot.Document(content:, ..) = jot.parse(cell)
  case content {
    [jot.Paragraph(_, content)] -> inline(content)
    _ -> [element.text(cell)]
  }
}

fn inline_text(content) {
  content
  |> list.map(fn(item) {
    case item {
      jot.Text(content) | jot.Code(content) -> content
      jot.Emphasis(content)
      | jot.Strong(content)
      | jot.Span(content:, ..)
      | jot.Link(content:, ..) -> inline_text(content)
      jot.Image(content:, ..) -> inline_text(content)
      jot.Linebreak | jot.NonBreakingSpace -> " "
      jot.Footnote(reference) -> reference
      jot.MathInline(content) | jot.MathDisplay(content) -> content
      jot.Delete(content: _) -> panic as "switch to pamphlet"
      jot.Insert(content: _) -> panic as "switch to pamphlet"
      jot.Mark(content: _) -> panic as "switch to pamphlet"
      jot.Superscript(content: _) -> panic as "switch to pamphlet"
      jot.Subscript(content: _) -> panic as "switch to pamphlet"
      jot.Symbol(content: _) -> panic as "switch to pamphlet"
    }
  })
  |> string.join("")
}

fn slug(content: String) {
  content
  |> string.lowercase
  |> string.to_graphemes
  |> list.map(fn(char) {
    case char {
      "a"
      | "b"
      | "c"
      | "d"
      | "e"
      | "f"
      | "g"
      | "h"
      | "i"
      | "j"
      | "k"
      | "l"
      | "m"
      | "n"
      | "o"
      | "p"
      | "q"
      | "r"
      | "s"
      | "t"
      | "u"
      | "v"
      | "w"
      | "x"
      | "y"
      | "z"
      | "0"
      | "1"
      | "2"
      | "3"
      | "4"
      | "5"
      | "6"
      | "7"
      | "8"
      | "9" -> char
      _ -> "-"
    }
  })
  |> string.join("")
  |> collapse_hyphens
  |> trim_hyphens
}

fn collapse_hyphens(content: String) {
  case string.contains(content, "--") {
    True -> string.replace(content, "--", "-") |> collapse_hyphens
    False -> content
  }
}

fn trim_hyphens(content: String) {
  content
  |> trim_start_hyphens
  |> trim_end_hyphens
}

fn trim_start_hyphens(content: String) {
  case string.starts_with(content, "-") {
    True -> string.drop_start(content, 1) |> trim_start_hyphens
    False -> content
  }
}

fn trim_end_hyphens(content: String) {
  case string.ends_with(content, "-") {
    True -> string.drop_end(content, 1) |> trim_end_hyphens
    False -> content
  }
}
