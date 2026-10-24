import etui/buffer
import etui/geometry
import etui/span
import etui/widgets/block
import etui/widgets/clear
import etui/widgets/input
import etui/widgets/paragraph
import eyg/cli/tui/state
import gleam/list
import gleam/string
import morph/lustre/frame
import morph/lustre/render
import morph/projection

pub fn render(state: state.State, screen: geometry.Rect) {
  let lines =
    render.expression(projection.rebuild(state.buffer.projection), [], [])
    |> code
    |> list.map(span.line_plain)

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

fn code(frame: frame.Frame) -> List(String) {
  case frame {
    frame.Inline(spans) ->
      list.map(spans, fn(span) { span.text }) |> string.concat() |> list.wrap
    frame.Multiline(pre, inner, post) -> {
      let pre = list.map(pre, fn(span) { span.text }) |> string.concat()
      let post = list.map(post, fn(span) { span.text }) |> string.concat()
      list.flatten([
        [pre],
        list.map(inner, code)
          |> list.flatten
          |> list.map(string.append("  ", _)),
        [post],
      ])
    }
    frame.Statements(frames) -> list.map(frames, code) |> list.flatten
  }
}
