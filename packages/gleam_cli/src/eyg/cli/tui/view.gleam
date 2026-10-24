import etui/buffer
import etui/geometry
import etui/widgets/paragraph
import eyg/cli/tui/state
import gleam/string
import morph/projection

pub fn render(state: state.State, screen: geometry.Rect) {
  buffer.buffer_new(screen)
  |> paragraph.render(
    screen,
    paragraph.paragraph_new(
      string.inspect(projection.rebuild(state.buffer.projection)),
    ),
  )
}
