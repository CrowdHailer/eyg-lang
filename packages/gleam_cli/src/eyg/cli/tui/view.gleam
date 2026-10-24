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
import morph/projection

pub fn render(state: state.State, screen: geometry.Rect) {
  let errors = infer.all_errors(state.buffer.analysis)

  let lines =
    render.top(projection.rebuild(state.buffer.projection), errors)
    |> frame.Statements
    |> code

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

fn code(frame: frame.Frame) -> List(span.Line) {
  case frame {
    frame.Inline(spans) -> list.wrap(line(spans))
    frame.Multiline(pre, inner, post) -> {
      list.flatten([
        [line(pre)],
        list.map(inner, code)
          |> list.flatten
          |> list.map(fn(line) {
            span.Line(..line, spans: [span.span_plain("  "), ..line.spans])
          }),
        [line(post)],
      ])
    }
    frame.Statements(frames) -> list.map(frames, code) |> list.flatten
  }
}

fn line(spans: List(frame.Span)) -> span.Line {
  let red = style.Rgb(255, 0, 0)

  list.map(spans, fn(span) {
    let style = case span.error {
      True ->
        style.underline_style()
        |> style.with_underline_color(red)
      False -> style.default_style()
    }
    span.span_styled(span.text, style)
  })
  |> span.line_new
}
