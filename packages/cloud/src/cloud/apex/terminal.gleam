//// A terminal in the browser, an etui buffer drawn as text with a span for each run of cells in the same style.
//// Key presses are sent to the server with the names etui uses for them, with `ctrl+`, `alt+` or `shift+` before them.
//// The page's `script` sends pasted text, the cell that is clicked and the number of cells that fit,
//// and leaves shortcuts such as copy to the browser.
////
//// A page can be shown beside the terminal, in a frame that cannot reach the terminal or anything else on its site.
//// On a wide screen it is on the right, on a narrow screen it fills most of the screen and the terminal is a strip above it.

import etui/buffer
import etui/geometry
import etui/style
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component

const foreground = "#ddd"

const background = "#181818"

const layout =
  "
.terminal { display: flex; height: 100vh; height: 100dvh; }
.terminal pre { flex: 1 1 0; min-width: 0; min-height: 0; box-sizing: border-box; overflow: hidden; }
.terminal iframe { flex: 1 1 0; min-width: 0; min-height: 0; border: 0; background: #fff; }
@media (max-width: 800px) {
  .terminal.beside { flex-direction: column; }
  .terminal.beside pre { flex: 0 0 auto; height: calc(12 * 1.15 * 14px + 2rem); }
}
"

/// The terminal, and the page at the `beside` url if there is one.
pub fn view(
  screen: buffer.Buffer,
  beside: Option(String),
  on_key: fn(String) -> msg,
  on_paste: fn(String) -> msg,
  on_resize: fn(Int, Int) -> msg,
  on_scroll: fn(Int) -> msg,
  on_click: fn(Int, Int) -> msg,
) -> Element(msg) {
  let terminal = text(screen, on_key, on_paste, on_resize, on_scroll, on_click)
  html.div(
    [
      attribute.class(case beside {
        Some(_) -> "terminal beside"
        None -> "terminal"
      }),
    ],
    [
      html.style([], layout),
      terminal,
      ..case beside {
        // Scripts in the page run, but it has its own origin so it cannot read anything of the terminal's site.
        Some(url) -> [
          html.iframe([
            attribute.src(url),
            attribute.attribute("sandbox", "allow-scripts"),
            attribute.attribute("referrerpolicy", "no-referrer"),
            attribute.title("Artifact"),
          ]),
        ]
        None -> []
      }
    ],
  )
}

fn text(screen, on_key, on_paste, on_resize, on_scroll, on_click) {
  html.pre(
    [
      attribute.tabindex(0),
      attribute.autofocus(True),
      attribute.attribute("aria-label", "EYG cloud"),
      attribute.style("font", "14px/1.15 monospace"),
      attribute.style("font-variant-ligatures", "none"),
      attribute.style("white-space", "pre"),
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
      // The wheel scrolls three lines a step, up is back.
      event.on("wheel", {
        use delta <- decode.field(
          "deltaY",
          decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)]),
        )
        case delta <. 0.0, delta >. 0.0 {
          True, _ -> decode.success(on_scroll(3))
          _, True -> decode.success(on_scroll(-3))
          _, _ -> decode.failure(on_scroll(0), "Scroll")
        }
      })
        |> server_component.include(["deltaY"])
        |> event.prevent_default,
      event.on("terminal-resize", {
        use columns <- decode.subfield(["detail", "columns"], decode.int)
        use rows <- decode.subfield(["detail", "rows"], decode.int)
        decode.success(on_resize(columns, rows))
      })
        |> server_component.include(["detail.columns", "detail.rows"]),
      event.on("terminal-click", {
        use column <- decode.subfield(["detail", "column"], decode.int)
        use row <- decode.subfield(["detail", "row"], decode.int)
        decode.success(on_click(column, row))
      })
        |> server_component.include(["detail.column", "detail.row"]),
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
/// Pasted text is sent to the terminal, and the cell that is clicked, and the number of cells that fit when it changes size.
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
function cell() {
  document.body.appendChild(probe);
  const box = probe.getBoundingClientRect();
  probe.remove();
  return { width: box.width / 100, height: box.height };
}
// The terminal has a padding of 16 pixels.
document.addEventListener('click', (event) => {
  const pre = terminal();
  if (!pre || !event.composedPath().includes(pre)) return;
  const size = cell();
  const box = pre.getBoundingClientRect();
  const column = Math.floor((event.clientX - box.left - 16) / size.width);
  const row = Math.floor((event.clientY - box.top - 16 + pre.scrollTop) / size.height);
  pre.dispatchEvent(new CustomEvent('terminal-click', { detail: { column, row } }));
});
// The size is sent again every few seconds, a connection that is made again starts a new terminal that does not know it.
let focused = false;
let observed = null;
function resize() {
  const pre = terminal();
  if (!pre) return;
  if (!focused) { pre.focus(); focused = true; }
  if (observed !== pre) { observed = pre; new ResizeObserver(resize).observe(pre); }
  const size = cell();
  const columns = Math.floor((pre.clientWidth - 32) / size.width);
  const rows = Math.floor((pre.clientHeight - 32) / size.height);
  pre.dispatchEvent(new CustomEvent('terminal-resize', { detail: { columns, rows } }));
}
window.addEventListener('resize', resize);
setInterval(resize, 2000);
const first = setInterval(() => { if (terminal()) { clearInterval(first); resize(); } }, 100);
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
