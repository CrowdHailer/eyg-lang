import etui/buffer
import etui/geometry
import etui/span
import etui/style
import etui/widgets/block
import etui/widgets/clear
import etui/widgets/input
import etui/widgets/paragraph
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/cli/tui/state
import gleam/list
import morph/lustre/frame
import morph/lustre/render

pub fn render(state: state.State, screen: geometry.Rect) {
  let errors = infer.all_errors(state.buffer.analysis)
  let active = case state.mode {
    state.Navigating -> True
    state.Manipulating(..) -> False
  }

  let lines =
    render.projection(state.buffer.projection, render.Statements, errors)
    |> code(active)

  let buf =
    buffer.buffer_new(screen)
    |> paragraph.render_styled(screen, lines)

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
      let area = geometry.centered_rect(50, 3, screen)
      let inner = block.inner(area, border)
      let buf = buf |> clear.render(area) |> block.render(area, border)
      case inner.size.width > 0 && inner.size.height > 0 {
        True -> input.render(buf, inner, widget, editing)
        False -> buf
      }
    }
  }
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
    frame.Plain | frame.Punctuation | frame.ClassName -> style.default_style()

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
  }
}
