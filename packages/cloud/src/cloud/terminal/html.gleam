//// Render styled terminal lines as a `<pre>` element.
////
//// The 16 standard colours use CSS variables `--ansi-0` to `--ansi-15`,
//// so a page theme decides how they look.
//// The 256 colour cube and RGB colours are written out directly.

import etui/span.{type Line, type Span}
import etui/style.{type Color}
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

pub fn lines(lines: List(Line)) -> List(Element(msg)) {
  list.map(lines, line)
}

/// One line of the terminal. Empty lines keep their height.
pub fn line(line: Line) -> Element(msg) {
  case line.spans {
    [] -> html.div([attribute.class("term-line")], [html.text("\n")])
    spans -> html.div([attribute.class("term-line")], list.map(spans, span))
  }
}

pub fn span(span: Span) -> Element(msg) {
  case style_attributes(span.style) {
    [] -> html.text(span.content)
    styles -> html.span(styles, [html.text(span.content)])
  }
}

pub fn style_attributes(s: style.Style) -> List(Attribute(msg)) {
  let reversed = style.has(s.modifier, style.reverse())
  let #(fg, bg) = case reversed {
    False -> #(color(s.fg), color(s.bg))
    True -> #(
      case color(s.bg) {
        "" -> "var(--term-bg)"
        c -> c
      },
      case color(s.fg) {
        "" -> "var(--term-fg)"
        c -> c
      },
    )
  }
  let declarations =
    [
      #("color", fg),
      #("background-color", bg),
      #("font-weight", flag(s, style.bold(), "bold")),
      #("opacity", flag(s, style.dim(), "0.65")),
      #("font-style", flag(s, style.italic(), "italic")),
      #(
        "text-decoration",
        [
          flag(s, style.underline(), "underline"),
          flag(s, style.strikethrough(), "line-through"),
        ]
          |> list.filter(fn(x) { x != "" })
          |> string.join(" "),
      ),
    ]
    |> list.filter(fn(declaration) { declaration.1 != "" })
  let styles = case declarations {
    [] -> []
    _ -> [attribute.styles(declarations)]
  }
  case style.has(s.modifier, style.blink()) {
    True -> [attribute.class("blink"), ..styles]
    False -> styles
  }
}

fn flag(s: style.Style, modifier, value) {
  case style.has(s.modifier, modifier) {
    True -> value
    False -> ""
  }
}

pub fn color(color: Color) -> String {
  case color {
    style.Default -> ""
    style.Indexed(n) if n >= 0 && n < 16 ->
      "var(--ansi-" <> int.to_string(n) <> ")"
    style.Indexed(n) if n >= 16 && n < 232 -> {
      let n = n - 16
      rgb(level(n / 36), level(n / 6 % 6), level(n % 6))
    }
    style.Indexed(n) if n >= 232 && n < 256 -> {
      let grey = 8 + { n - 232 } * 10
      rgb(grey, grey, grey)
    }
    style.Indexed(_) -> ""
    style.Rgb(r, g, b) -> rgb(r, g, b)
  }
}

fn level(n) {
  case n {
    0 -> 0
    _ -> 55 + n * 40
  }
}

fn rgb(r, g, b) {
  "rgb("
  <> int.to_string(r)
  <> ","
  <> int.to_string(g)
  <> ","
  <> int.to_string(b)
  <> ")"
}
