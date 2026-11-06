//// EYG code as styled terminal lines.
////
//// Code is rendered by morph into frames, the same as the CLI's TUI,
//// and each frame becomes one or more lines of styled spans.

import etui/span.{type Line}
import etui/style.{type Style}
import gleam/list
import gleam/string
import morph/buffer.{type Buffer}
import morph/editable as e
import morph/lustre/frame
import morph/lustre/render

/// The code being edited, with the selection highlighted.
/// The highlight is dimmed when `active` is false, such as while a
/// dialog has the keyboard.
pub fn editing(buffer: Buffer, active: Bool) -> List(Line) {
  render.projection(
    buffer.projection,
    render.Statements,
    buffer.block_errors(buffer),
  )
  |> frame_lines(active)
}

/// Code that is no longer being edited.
pub fn lines(expression: e.Expression) -> List(Line) {
  render.statements(expression, [])
  |> list.flat_map(frame_lines(_, False))
}

/// Code as plain text, one line per rendered line.
pub fn to_text(expression: e.Expression) -> String {
  lines(expression)
  |> list.map(fn(line) {
    list.map(line.spans, fn(s) { s.content }) |> string.concat
  })
  |> string.join("\n")
}

fn frame_lines(value: frame.Frame, active: Bool) -> List(Line) {
  case value {
    frame.Inline(spans) -> [line(spans, active)]
    frame.Multiline([], inner, []) | frame.Statements(inner) ->
      list.flat_map(inner, frame_lines(_, active))
    frame.Multiline(pre, inner, post) -> {
      // Indent the whole selected structure, but not a selected child alone.
      let focused =
        list.any(pre, fn(s) { s.focus })
        && list.any(post, fn(s) { s.focus })
        && list.all(inner, frame.fully_focused)
      let indent =
        span.span_styled(
          "  ",
          focus_style(style.default_style(), focused, active),
        )
      list.flatten([
        [line(pre, active)],
        list.flat_map(inner, frame_lines(_, active))
          |> list.map(fn(line) {
            span.Line(..line, spans: [indent, ..line.spans])
          }),
        [line(post, active)],
      ])
    }
  }
}

fn line(spans: List(frame.Span), active: Bool) -> Line {
  list.map(spans, fn(s) {
    let base = syntax_style(s.token_type)
    let base = case s.error {
      True ->
        base
        |> style.add_modifier(style.underline())
        |> style.with_underline_color(style.Indexed(1))
      False -> base
    }
    span.span_styled(s.text, focus_style(base, s.focus, active))
  })
  |> span.line_new
}

fn focus_style(base: Style, focused: Bool, active: Bool) -> Style {
  case focused, active {
    False, _ -> base
    True, True ->
      base
      |> style.with_fg(style.Default)
      |> style.with_bg(style.Default)
      |> style.add_modifier(style.reverse())
    True, False ->
      base
      |> style.add_modifier(style.underline())
  }
}

fn syntax_style(token_type: frame.TokenType) -> Style {
  let plain = style.default_style()
  case token_type {
    frame.Plain | frame.Punctuation -> plain
    frame.Comment -> style.add_modifier(plain, style.dim())
    frame.Number | frame.Symbol -> style.with_fg(plain, style.Indexed(5))
    frame.String | frame.Char | frame.Builtin ->
      style.with_fg(plain, style.Indexed(2))
    frame.Keyword -> style.with_fg(plain, style.Indexed(6))
    frame.Variable -> style.with_fg(plain, style.Indexed(3))
    frame.Important ->
      style.with_fg(plain, style.Indexed(3)) |> style.add_modifier(style.bold())
    frame.ClassName ->
      style.with_fg(plain, style.Indexed(12))
      |> style.add_modifier(style.bold())
  }
}
