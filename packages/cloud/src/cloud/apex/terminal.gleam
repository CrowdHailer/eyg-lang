//// A terminal in the browser, an etui buffer drawn as text with a span for each run of cells in the same style.
//// Key presses are sent to the server with the names etui uses for them.

import etui/buffer
import etui/geometry
import etui/style
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component

const foreground = "#ddd"

const background = "#181818"

pub fn view(screen: buffer.Buffer, on_key: fn(String) -> msg) -> Element(msg) {
  html.pre(
    [
      attribute.tabindex(0),
      attribute.autofocus(True),
      attribute.attribute("aria-label", "EYG cloud"),
      attribute.style("font", "14px/1.15 monospace"),
      attribute.style("font-variant-ligatures", "none"),
      attribute.style("white-space", "pre"),
      attribute.style("overflow", "auto"),
      attribute.style("margin", "0"),
      attribute.style("outline", "none"),
      attribute.style("padding", "1rem"),
      attribute.style("color", foreground),
      attribute.style("background", background),
      event.on("keydown", key(on_key))
        |> server_component.include(["key"])
        |> event.prevent_default,
    ],
    list.repeat(Nil, buffer.height(screen))
      |> list.index_map(fn(_, y) {
        list.repeat(Nil, buffer.width(screen))
        |> list.index_map(fn(_, x) {
          buffer.get_cell(screen, geometry.Position(x, y))
        })
        |> runs([])
        |> list.map(run)
        |> list.append([html.text("\n")])
      })
      |> list.flatten,
  )
}

// Keys that only modify others, such as Shift, are not sent.
fn key(on_key) {
  use key <- decode.field("key", decode.string)
  let named = [
    #("ArrowUp", "up"),
    #("ArrowDown", "down"),
    #("ArrowLeft", "left"),
    #("ArrowRight", "right"),
    #("Escape", "esc"),
    #("Enter", "enter"),
    #("Backspace", "backspace"),
    #("Delete", "delete"),
    #("Home", "home"),
    #("End", "end"),
    #("Tab", "tab"),
  ]
  case list.key_find(named, key), string.length(key) {
    Ok(name), _ -> decode.success(on_key(name))
    Error(Nil), 1 -> decode.success(on_key(key))
    Error(Nil), _ -> decode.failure(on_key(key), "Key")
  }
}

// Cells in the same style, newest first. The second cell of a wide character has no content.
fn runs(cells: List(buffer.Cell), acc) {
  case cells, acc {
    [], _ -> list.reverse(acc)
    [buffer.Cell(content: buffer.Continuation, ..), ..cells], _ ->
      runs(cells, acc)
    [buffer.Cell(content: buffer.Content(symbol, _), style:, ..), ..cells],
      [#(previous, text), ..acc]
      if previous == style
    -> runs(cells, [#(style, text <> symbol), ..acc])
    [buffer.Cell(content: buffer.Content(symbol, _), style:, ..), ..cells], _ ->
      runs(cells, [#(style, symbol), ..acc])
  }
}

fn run(run: #(style.Style, String)) {
  let #(s, text) = run
  let fg = color(s.fg, foreground)
  let bg = color(s.bg, background)
  let #(fg, bg) = case style.has(s.modifier, style.reverse()) {
    True -> #(bg, fg)
    False -> #(fg, bg)
  }
  let flag = fn(modifier, on, off) {
    case style.has(s.modifier, modifier) {
      True -> on
      False -> off
    }
  }
  html.span(
    [
      attribute.style("color", fg),
      attribute.style("background", bg),
      attribute.style("font-weight", flag(style.bold(), "bold", "normal")),
      attribute.style("opacity", flag(style.dim(), "0.65", "1")),
      attribute.style(
        "text-decoration-line",
        flag(style.underline(), "underline", "none"),
      ),
    ],
    [html.text(text)],
  )
}

fn color(color: style.Color, default: String) -> String {
  case color {
    style.Default -> default
    style.Rgb(r, g, b) ->
      "rgb(" <> string.join(list.map([r, g, b], int.to_string), ",") <> ")"
    style.Indexed(index) ->
      [
        background, "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd",
        "#56b6c2", foreground, "#666", "#e06c75", "#98c379", "#e5c07b",
        "#61afef", "#c678dd", "#56b6c2", "#fff",
      ]
      |> list.drop(index)
      |> list.first
      |> result.unwrap(default)
  }
}
