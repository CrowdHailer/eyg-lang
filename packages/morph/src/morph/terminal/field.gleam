//// A line of text being typed, such as a name or a number, in a terminal.
////
//// Keys edit at the cursor and move it, as in a text field. The cursor is drawn as a reversed cell,
//// so it shows where there is no terminal cursor, such as a terminal drawn in a web page.

import etui/buffer
import etui/geometry
import etui/keys
import etui/span
import etui/style
import etui/text
import etui/widgets/block
import etui/widgets/clear
import etui/widgets/input
import etui/widgets/paragraph
import gleam/int

/// Apply a key to the text, keys that do not edit or move leave it as it is.
pub fn edit(
  widget: input.InputWidget,
  editing: input.InputState,
  key: String,
) -> input.InputState {
  case key {
    "ctrl+a" -> input.move_to_start(editing)
    "ctrl+e" -> input.move_to_end(editing)
    "ctrl+u" -> input.clear_state(editing)
    "ctrl+k" -> input.delete_to_end(editing)
    _ -> edit_key(widget, editing, key)
  }
}

fn edit_key(
  widget: input.InputWidget,
  editing: input.InputState,
  key: String,
) -> input.InputState {
  case keys.parse(key) {
    keys.KeyEvent(code, keys.Modifiers(ctrl: False, alt: False, ..)) ->
      case code {
        keys.Char(char) -> input.insert_char(widget, editing, char)
        keys.Backspace -> input.backspace(editing)
        keys.Left -> input.move_cursor_left(editing)
        keys.Right -> input.move_cursor_right(editing)
        keys.Home -> input.move_to_start(editing)
        keys.End -> input.move_to_end(editing)
        keys.Delete -> {
          let moved = input.move_cursor_right(editing)
          case moved.cursor == editing.cursor {
            True -> editing
            False -> input.backspace(moved)
          }
        }
        _ -> editing
      }
    _ -> editing
  }
}

/// Draw the text on one line of the area with the cursor, scrolled so the cursor shows.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  widget: input.InputWidget,
  editing: input.InputState,
) -> buffer.Buffer {
  case area.size.width > 0 && area.size.height > 0 {
    False -> buf
    True ->
      input.render(buf, area, widget, editing) |> cursor(area, widget, editing)
  }
}

/// Draw the cursor over text drawn with `input.render`.
pub fn cursor(
  buf: buffer.Buffer,
  area: geometry.Rect,
  widget: input.InputWidget,
  editing: input.InputState,
) -> buffer.Buffer {
  case area.size.width > 0 && area.size.height > 0 {
    False -> buf
    True -> {
      // The column of the cursor, as `input.render` scrolls the text.
      let column = text.cell_width(widget.prompt) + editing.cursor
      let column = int.min(column, area.size.width - 1)
      let position =
        geometry.Position(area.position.x + column, area.position.y)
      let symbol = case buffer.cell_symbol(buffer.get_cell(buf, position)) {
        "" -> " "
        symbol -> symbol
      }
      buffer.set_string(
        buf,
        position,
        symbol,
        style.new(widget.fg, widget.bg, style.reverse()),
      )
    }
  }
}

/// A box with a title in the middle of the area, with the text being typed and what to do next,
/// or why the text is not valid.
pub fn dialog(
  buf: buffer.Buffer,
  area: geometry.Rect,
  title: String,
  widget: input.InputWidget,
  editing: input.InputState,
) -> buffer.Buffer {
  let message = case input.validate(widget, editing.value) {
    Ok(_) ->
      span.span_styled(
        "Enter apply · Esc cancel",
        style.default_style() |> style.add_modifier(style.dim()),
      )
    Error(message) ->
      span.span_styled(
        message,
        style.default_style() |> style.with_fg(widget.error_fg),
      )
  }
  let border =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title(title, block.Top)
    |> block.with_padding(0, 0, 1, 1)
  let area = centered(area, 5)
  let inner = block.inner(area, border)
  let buf = buf |> clear.render(area) |> block.render(area, border)
  case inner.size.width > 0 && inner.size.height > 0 {
    True -> {
      let assert [line, _, feedback] =
        geometry.split_v(inner, [
          geometry.Length(1),
          geometry.Fill,
          geometry.Length(1),
        ])
      buf
      |> render(line, widget, editing)
      |> paragraph.render_styled(feedback, [span.line_new([message])])
    }
    False -> buf
  }
}

/// A box `height` rows high in the middle of the area, as wide as fits up to 72 columns.
pub fn centered(area: geometry.Rect, height: Int) -> geometry.Rect {
  let margin = case area.size.width >= 40 {
    True -> 4
    False -> 0
  }
  geometry.centered_rect(
    int.min(72, area.size.width - margin),
    int.min(height, area.size.height),
    area,
  )
}
