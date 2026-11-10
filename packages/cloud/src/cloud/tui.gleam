import etui/backend
import etui/buffer
import etui/geometry
import etui/style
import eyg/cli/tui/state
import eyg/cli/tui/view as tui_view
import eyg/hub/cache
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import loam/execute
import lustre
import lustre/attribute
import lustre/element/html
import lustre/event
import lustre/server_component
import ogre/origin

pub fn app() {
  lustre.simple(
    fn(_) {
      state.init([], execute.State(origin.http("localhost"), cache.ready()))
    },
    fn(model, input) {
      // Module loading and effects will be wired up later.
      let #(model, _) = state.update(model, state.Input(input))
      model
    },
    view,
  )
}

fn view(model: state.State) {
  let screen = tui_view.render(model, geometry.rect_new(0, 0, 100, 30))
  html.pre(
    [
      attribute.tabindex(0),
      attribute.attribute("aria-label", "EYG shell"),
      attribute.style("font", "14px/1.2 monospace"),
      attribute.style("font-variant-ligatures", "none"),
      attribute.style("white-space", "pre"),
      attribute.style("overflow", "auto"),
      attribute.style("padding", "1rem"),
      attribute.style("color", "#ddd"),
      attribute.style("background", "#181818"),
      event.on("keydown", key())
        |> server_component.include(["key"])
        |> event.prevent_default,
    ],
    list.repeat(Nil, buffer.height(screen))
      |> list.index_map(fn(_, y) {
        list.repeat(Nil, buffer.width(screen))
        |> list.index_map(fn(_, x) {
          screen |> buffer.get_cell(geometry.Position(x, y)) |> cell
        })
        |> list.append([html.text("\n")])
      })
      |> list.flatten,
  )
}

fn key() {
  use key <- decode.field("key", decode.string)
  let key = case key {
    "ArrowUp" -> "up"
    "ArrowDown" -> "down"
    "ArrowLeft" -> "left"
    "ArrowRight" -> "right"
    "Escape" -> "esc"
    "Enter" -> "enter"
    "Backspace" -> "backspace"
    "Delete" -> "delete"
    "Home" -> "home"
    "End" -> "end"
    _ -> key
  }
  decode.success(backend.KeyPress(key))
}

fn cell(cell: buffer.Cell) {
  case cell.content {
    buffer.Continuation -> html.text("")
    buffer.Content(symbol, width) -> {
      let s = cell.style
      let fg = color(s.fg, "#ddd")
      let bg = color(s.bg, "#181818")
      let #(fg, bg) = case style.has(s.modifier, style.reverse()) {
        True -> #(bg, fg)
        False -> #(fg, bg)
      }
      html.span(
        [
          attribute.style("display", "inline-block"),
          attribute.style("width", int.to_string(width) <> "ch"),
          attribute.style("color", fg),
          attribute.style("background", bg),
          attribute.style("text-decoration-color", color(s.underline_color, fg)),
          attribute.style(
            "font-weight",
            case style.has(s.modifier, style.bold()) {
              True -> "bold"
              False -> "normal"
            },
          ),
          attribute.style("opacity", case style.has(s.modifier, style.dim()) {
            True -> "0.65"
            False -> "1"
          }),
          attribute.style(
            "text-decoration-line",
            case style.has(s.modifier, style.underline()) {
              True -> "underline"
              False -> "none"
            },
          ),
        ],
        [html.text(symbol)],
      )
    }
  }
}

fn color(color: style.Color, default: String) -> String {
  case color {
    style.Default -> default
    style.Rgb(r, g, b) ->
      "rgb(" <> string.join(list.map([r, g, b], int.to_string), ",") <> ")"
    style.Indexed(index) ->
      [
        "#181818", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd",
        "#56b6c2", "#ddd", "#666", "#e06c75", "#98c379", "#e5c07b", "#61afef",
        "#c678dd", "#56b6c2", "#fff",
      ]
      |> list.drop(index)
      |> list.first
      |> result.unwrap(default)
  }
}
