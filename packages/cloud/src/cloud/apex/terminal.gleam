//// A terminal in the browser, an etui buffer drawn as text with a span for each run of cells in the same style.
//// Key presses are sent to the server with the names etui uses for them, with `ctrl+`, `alt+` or `shift+` before them.
//// The page's `script` sends pasted text and the number of cells that fit, and leaves shortcuts such as copy to the browser.

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

pub fn view(
  screen: buffer.Buffer,
  on_key: fn(String) -> msg,
  on_paste: fn(String) -> msg,
  on_resize: fn(Int, Int) -> msg,
) -> Element(msg) {
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
        |> server_component.include([
          "key", "ctrlKey", "metaKey", "altKey", "shiftKey",
        ]),
      event.on(
        "terminal-paste",
        decode.at(["detail"], decode.string) |> decode.map(on_paste),
      )
        |> server_component.include(["detail"]),
      event.on("terminal-resize", {
        use columns <- decode.subfield(["detail", "columns"], decode.int)
        use rows <- decode.subfield(["detail", "rows"], decode.int)
        decode.success(on_resize(columns, rows))
      })
        |> server_component.include(["detail.columns", "detail.rows"]),
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

// Keys that only modify others, such as Shift, are not sent on their own.
// Shift is only named for keys that are not characters, a shifted character is already different.
fn key(on_key) {
  use key <- decode.field("key", decode.string)
  use ctrl <- decode.field("ctrlKey", decode.bool)
  use meta <- decode.field("metaKey", decode.bool)
  use alt <- decode.field("altKey", decode.bool)
  use shift <- decode.field("shiftKey", decode.bool)
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
    #("PageUp", "pageup"),
    #("PageDown", "pagedown"),
  ]
  let modifiers = fn(name, shifted) {
    let name = case shifted {
      True -> "shift+" <> name
      False -> name
    }
    let name = case alt {
      True -> "alt+" <> name
      False -> name
    }
    case ctrl || meta {
      True -> "ctrl+" <> name
      False -> name
    }
  }
  case list.key_find(named, key), string.length(key) {
    Ok(name), _ -> decode.success(on_key(modifiers(name, shift)))
    Error(Nil), 1 -> decode.success(on_key(modifiers(key, False)))
    Error(Nil), _ -> decode.failure(on_key(key), "Key")
  }
}

/// The script for the page the terminal is on.
/// Keys the terminal uses do nothing else on the page, keys with ctrl or meta and function keys keep doing what the browser does,
/// such as copy and full screen.
/// Pasted text is sent to the terminal, and the number of cells that fit the window when it changes size.
pub const script =
  "
const terminal = () => document.querySelector('lustre-server-component')?.shadowRoot?.querySelector('pre');
document.addEventListener('keydown', (event) => {
  const pre = terminal();
  // Function keys, such as F11 for full screen, are left to the browser too.
  const shortcut = event.ctrlKey || event.metaKey || /^F[0-9]+$/.test(event.key);
  if (pre && event.composedPath().includes(pre) && !shortcut) event.preventDefault();
}, true);
document.addEventListener('paste', (event) => {
  const pre = terminal();
  if (!pre) return;
  event.preventDefault();
  pre.dispatchEvent(new CustomEvent('terminal-paste', { detail: event.clipboardData.getData('text') }));
});
const probe = document.createElement('span');
probe.style = 'position: absolute; visibility: hidden; font: 14px/1.15 monospace; white-space: pre';
probe.textContent = 'x'.repeat(100);
function resize() {
  const pre = terminal();
  if (!pre) return setTimeout(resize, 200);
  pre.focus();
  document.body.appendChild(probe);
  const cell = probe.getBoundingClientRect();
  probe.remove();
  const columns = Math.floor((window.innerWidth - 32) / (cell.width / 100));
  const rows = Math.floor((window.innerHeight - 32) / cell.height);
  pre.dispatchEvent(new CustomEvent('terminal-resize', { detail: { columns, rows } }));
}
window.addEventListener('resize', resize);
resize();
"

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
