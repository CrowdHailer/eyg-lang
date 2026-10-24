import etui/buffer
import etui/geometry
import etui/widgets/paragraph
import eyg/cli/tui/state

pub fn render(state: state.State, screen: geometry.Rect) {
  buffer.buffer_new(screen)
  |> paragraph.render(screen, paragraph.paragraph_new(state.text))
}
