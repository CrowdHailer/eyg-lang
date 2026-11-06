//// Turn text containing ANSI escape codes into styled lines.
////
//// Select Graphic Rendition (SGR) codes set the style of the text after them.
//// Any other control sequence is dropped, the shell has no cursor to move.

import etui/span.{type Line}
import etui/style.{type Color, type Style}
import gleam/int
import gleam/list
import gleam/string

/// Parse `text` starting in `base` style.
/// A reset returns to `base` rather than to the terminal default.
pub fn parse(text: String, base: Style) -> List(Line) {
  let #(done, current, _) =
    string.split(text, "\u{1b}[")
    |> list.index_fold(#([], [], base), fn(acc, part, index) {
      let #(done, current, active) = acc
      case index {
        0 -> add_text(done, current, part, active)
        _ -> {
          let #(parameters, final, rest) = split_sequence(part)
          let active = case final {
            "m" -> apply(active, base, parameters)
            _ -> active
          }
          add_text(done, current, rest, active)
        }
      }
    })
  let lines = case current, done {
    // A final newline ends the last line rather than starting a new one.
    [], [_, ..] -> done
    _, _ -> [current, ..done]
  }
  list.reverse(lines)
  |> list.map(fn(spans) { span.line_new(list.reverse(spans)) })
}

// `done` holds finished lines and `current` the line in progress,
// both newest first.
fn add_text(done, current, text, active) {
  let assert [first, ..rest] = string.split(text, "\n")
  let current = push(current, first, active)
  list.fold(rest, #(done, current, active), fn(acc, segment) {
    let #(done, current, active) = acc
    #([current, ..done], push([], segment, active), active)
  })
}

fn push(spans, text, active) {
  let text = string.replace(text, "\r", "")
  case text {
    "" -> spans
    _ -> [span.span_styled(text, active), ..spans]
  }
}

/// Split a control sequence after `ESC [` into parameters, final byte and
/// the text that follows.
fn split_sequence(part: String) -> #(String, String, String) {
  do_split_sequence(part, "")
}

fn do_split_sequence(part, parameters) {
  case string.pop_grapheme(part) {
    Error(Nil) -> #(parameters, "", "")
    Ok(#(char, rest)) ->
      case is_final(char) {
        True -> #(parameters, char, rest)
        False -> do_split_sequence(rest, parameters <> char)
      }
  }
}

fn is_final(char) {
  case string.to_utf_codepoints(char) {
    [codepoint] -> {
      let code = string.utf_codepoint_to_int(codepoint)
      code >= 0x40 && code <= 0x7e
    }
    _ -> False
  }
}

fn apply(active: Style, base: Style, parameters: String) -> Style {
  let codes =
    string.split(parameters, ";")
    |> list.map(fn(code) {
      case code {
        "" -> 0
        _ ->
          case int.parse(code) {
            Ok(code) -> code
            Error(Nil) -> -1
          }
      }
    })
  do_apply(active, base, codes)
}

fn do_apply(s: Style, base: Style, codes: List(Int)) -> Style {
  case codes {
    [] -> s
    [0, ..rest] -> do_apply(base, base, rest)
    [38, 5, n, ..rest] ->
      do_apply(style.with_fg(s, style.Indexed(n)), base, rest)
    [48, 5, n, ..rest] ->
      do_apply(style.with_bg(s, style.Indexed(n)), base, rest)
    [38, 2, r, g, b, ..rest] ->
      do_apply(style.with_fg(s, style.Rgb(r, g, b)), base, rest)
    [48, 2, r, g, b, ..rest] ->
      do_apply(style.with_bg(s, style.Rgb(r, g, b)), base, rest)
    [code, ..rest] -> do_apply(single(s, base, code), base, rest)
  }
}

fn single(s: Style, base: Style, code: Int) -> Style {
  case code {
    1 -> modify(s, style.add, style.bold())
    2 -> modify(s, style.add, style.dim())
    3 -> modify(s, style.add, style.italic())
    4 -> modify(s, style.add, style.underline())
    7 -> modify(s, style.add, style.reverse())
    9 -> modify(s, style.add, style.strikethrough())
    22 ->
      s
      |> modify(style.remove, style.bold())
      |> modify(style.remove, style.dim())
    23 -> modify(s, style.remove, style.italic())
    24 -> modify(s, style.remove, style.underline())
    27 -> modify(s, style.remove, style.reverse())
    29 -> modify(s, style.remove, style.strikethrough())
    39 -> style.with_fg(s, base.fg)
    49 -> style.with_bg(s, base.bg)
    _ if code >= 30 && code <= 37 -> style.with_fg(s, indexed(code - 30))
    _ if code >= 40 && code <= 47 -> style.with_bg(s, indexed(code - 40))
    _ if code >= 90 && code <= 97 -> style.with_fg(s, indexed(code - 82))
    _ if code >= 100 && code <= 107 -> style.with_bg(s, indexed(code - 92))
    _ -> s
  }
}

fn indexed(n: Int) -> Color {
  style.Indexed(n)
}

fn modify(s: Style, f, modifier) -> Style {
  style.Style(..s, modifier: f(s.modifier, modifier))
}
