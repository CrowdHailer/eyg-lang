import etui/buffer
import etui/geometry
import etui/span
import etui/style
import etui/text
import etui/widgets/block
import etui/widgets/clear
import etui/widgets/input
import etui/widgets/paragraph
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/cli/tui/state
import eyg/interpreter/simple_debug
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import morph/lustre/frame
import morph/lustre/render
import morph/projection
import morph/repl/history

pub fn render(state: state.State, screen: geometry.Rect) {
  let errors = infer.all_errors(state.buffer.analysis)
  let message_lines = text.wrap(state.message, screen.size.width)
  let message_height =
    int.min(
      list.length(message_lines),
      int.max(0, screen.size.height - list.length(errors) - 1),
    )
  let assert [code_area, error_area, message_area] =
    geometry.split_v(screen, [
      geometry.Fill,
      geometry.Length(list.length(errors)),
      geometry.Length(message_height),
    ])
  let active = case state.mode {
    state.Navigating -> True
    state.Manipulating(..) -> False
  }

  let input_lines =
    render.projection(state.buffer.projection, render.Statements, errors)
    |> code(active)
  let lines =
    state.history
    |> list.reverse
    |> list.flat_map(history_lines(_, code_area.size.width))
    |> list.append(input_lines)
  let line_count = list.length(lines)
  let visible_height = int.min(line_count, code_area.size.height)
  let content_area =
    geometry.rect_new(
      code_area.position.x,
      geometry.bottom(code_area) - visible_height,
      code_area.size.width,
      visible_height,
    )
  // Like a shell, keep the end of the program visible as it grows upward.
  let lines = list.drop(lines, int.max(0, line_count - visible_height))

  let message_style = style.default_style() |> style.with_bg(style.Indexed(5))
  let buf =
    buffer.buffer_new(screen)
    |> paragraph.render_styled(content_area, lines)
    |> paragraph.render_styled(error_area, error_lines(errors))
    |> buffer.set_style(message_area, message_style)
    |> paragraph.render_styled(
      message_area,
      list.map(message_lines, fn(line) {
        span.line_new([span.span_styled(line, message_style)])
      }),
    )

  case state.mode {
    state.Navigating -> buf
    state.Manipulating(editing, kind) -> {
      let widget = state.input_widget(kind)
      let title = case input.validate(widget, editing.value) {
        Ok(_) -> "Enter: apply | Esc: cancel"
        Error(message) -> message
      }
      let border =
        block.block_new()
        |> block.with_border(block.Rounded)
        |> block.with_title(title, block.Top)
      let area = geometry.centered_rect(50, 3, code_area)
      let inner = block.inner(area, border)
      let buf = buf |> clear.render(area) |> block.render(area, border)
      case inner.size.width > 0 && inner.size.height > 0 {
        True -> input.render(buf, inner, widget, editing)
        False -> buf
      }
    }
  }
}

fn history_lines(entry: history.Entry(a), width: Int) -> List(span.Line) {
  let lines =
    entry.buffer.projection
    |> projection.rebuild
    |> render.statements([])
    |> list.flat_map(code(_, False))
  case entry.value {
    None -> lines
    Some(value) -> {
      let value_lines =
        simple_debug.render(value, int.max(1, width - 2))
        |> string.split("\n")
        |> list.index_map(fn(line, index) {
          let prefix = case index {
            0 -> "= "
            _ -> "  "
          }
          span.line_new([
            span.span_styled(prefix <> line, style.default_style()),
          ])
        })
      list.append(lines, value_lines)
    }
  }
}

fn error_lines(errors) -> List(span.Line) {
  let error_style = style.default_style() |> style.with_fg(style.Indexed(1))
  list.map(errors, fn(error) {
    let #(_path, reason) = error
    // Type formatting can introduce line breaks; each diagnostic gets one row.
    let message =
      debug.reason(reason)
      |> string.replace("\r\n", " ")
      |> string.replace("\n", " ")
      |> string.replace("\r", " ")
      |> string.replace("\t", " ")
    span.line_new([span.span_styled("error: " <> message, error_style)])
  })
}

fn code(value: frame.Frame, active: Bool) -> List(span.Line) {
  case value {
    frame.Inline(spans) -> list.wrap(line(spans, active))
    frame.Multiline([], inner, []) | frame.Statements(inner) ->
      list.flat_map(inner, code(_, active))
    frame.Multiline(pre, inner, post) -> {
      // Indent the whole selected structure, but not a selected child alone.
      // Its boundary lines may also contain unselected context or delimiters.
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
        list.flat_map(inner, code(_, active))
          |> list.map(fn(line) {
            span.Line(..line, spans: [indent, ..line.spans])
          }),
        [line(post, active)],
      ])
    }
  }
}

fn line(spans: List(frame.Span), active: Bool) -> span.Line {
  let red = style.Rgb(255, 0, 0)

  list.map(spans, fn(span) {
    let base = syntax_style(span.token_type)
    let style = case span.error {
      True ->
        base
        |> style.add_modifier(style.underline())
        |> style.with_underline_color(red)
      False -> base
    }
    let style = focus_style(style, span.focus, active)
    span.span_styled(span.text, style)
  })
  |> span.line_new
}

fn focus_style(base: style.Style, focused: Bool, active: Bool) -> style.Style {
  case focused, active {
    False, _ -> base
    True, True ->
      base
      |> style.with_fg(style.Default)
      |> style.with_bg(style.Default)
      |> style.add_modifier(style.reverse())
    True, False ->
      base
      |> style.add_modifier(style.dim())
      |> style.add_modifier(style.underline())
  }
}

fn syntax_style(token_type: frame.TokenType) -> style.Style {
  case token_type {
    frame.Plain | frame.Punctuation -> style.default_style()

    frame.Comment ->
      style.default_style()
      |> style.add_modifier(style.dim())

    frame.Number | frame.Symbol ->
      style.default_style()
      |> style.with_fg(style.Indexed(5))

    frame.String | frame.Char | frame.Builtin ->
      style.default_style()
      |> style.with_fg(style.Indexed(2))

    frame.Keyword ->
      style.default_style()
      |> style.with_fg(style.Indexed(6))

    frame.Variable ->
      style.default_style()
      |> style.with_fg(style.Indexed(3))

    frame.Important ->
      style.default_style()
      |> style.with_fg(style.Indexed(3))
      |> style.add_modifier(style.bold())
    frame.ClassName ->
      style.default_style()
      |> style.with_fg(style.Indexed(12))
      |> style.add_modifier(style.bold())
  }
}
