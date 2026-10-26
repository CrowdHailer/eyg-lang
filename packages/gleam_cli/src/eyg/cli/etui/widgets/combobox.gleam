/// Editable text with prefix suggestions. Enter submits the text; Tab completes
/// to the next branching point, following the highlighted item at a split.
import etui/backend
import etui/geometry
import etui/keys
import etui/span
import etui/style
import etui/text
import etui/widgets/input
import etui/widgets/list as select
import etui/widgets/paragraph
import gleam/int
import gleam/list
import gleam/string

pub type Combobox {
  Combobox(
    items: List(#(String, String)),
    input: input.InputState,
    selection: select.ListState,
  )
}

pub type Action {
  Updated(Combobox)
  Selected(String)
  Cancelled
}

pub fn new(items: List(#(String, String))) -> Combobox {
  Combobox(items, input.state_new(), select.state_new())
}

fn matches(box: Combobox) -> List(#(String, String)) {
  let query = string.lowercase(box.input.value)
  list.filter(box.items, fn(item) {
    string.starts_with(string.lowercase(item.0), query)
  })
}

pub fn update(event: backend.InputEvent, box: Combobox) -> Action {
  case event {
    backend.KeyPress("esc") -> Cancelled
    backend.KeyPress("enter") -> Selected(box.input.value)
    backend.KeyPress("tab") ->
      with_input(box, input.state_from_string(completion(box)))
    backend.KeyPress("up") ->
      Updated(Combobox(..box, selection: select.select_prev(box.selection)))
    backend.KeyPress("down") ->
      Updated(
        Combobox(
          ..box,
          selection: select.select_next(
            box.selection,
            list.length(matches(box)),
          ),
        ),
      )
    backend.KeyPress(key) -> with_input(box, edit_input(box.input, key))
    backend.Paste(text) -> {
      let edited =
        text
        |> string.replace("\r", "")
        |> string.replace("\n", " ")
        |> string.to_graphemes
        |> list.fold(box.input, fn(editing, char) {
          input.insert_char(input.input_new(""), editing, char)
        })
      with_input(box, edited)
    }
    _ -> Updated(box)
  }
}

fn completion(box: Combobox) -> String {
  let items = matches(box)
  case list.first(list.drop(items, box.selection.selected)) {
    Error(_) -> box.input.value
    Ok(#(selected, _)) -> {
      let shared: String =
        list.fold(items, selected, fn(acc, item) { common_prefix(acc, item.0) })
      case string.length(shared) > string.length(box.input.value) {
        True -> shared
        False -> {
          let branch =
            string.slice(selected, 0, string.length(box.input.value) + 1)
          items
          |> list.filter(fn(item) {
            string.starts_with(
              string.lowercase(item.0),
              string.lowercase(branch),
            )
          })
          |> list.fold(selected, fn(acc, item) { common_prefix(acc, item.0) })
        }
      }
    }
  }
}

fn common_prefix(left: String, right: String) -> String {
  case string.pop_grapheme(left), string.pop_grapheme(right) {
    Ok(#(a, left)), Ok(#(b, right)) ->
      case string.lowercase(a) == string.lowercase(b) {
        True -> a <> common_prefix(left, right)
        False -> ""
      }
    _, _ -> ""
  }
}

fn with_input(box: Combobox, edited: input.InputState) -> Action {
  let selection = case edited.value == box.input.value {
    True -> box.selection
    False -> select.state_new()
  }
  Updated(Combobox(..box, input: edited, selection:))
}

fn edit_input(editing: input.InputState, key: String) -> input.InputState {
  case keys.parse(key) {
    keys.KeyEvent(code, keys.Modifiers(ctrl: False, alt: False, ..)) ->
      case code {
        keys.Char(char) -> input.insert_char(input.input_new(""), editing, char)
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

pub fn render(buf, area: geometry.Rect, box: Combobox) {
  case area.size.width > 0 && area.size.height > 0 {
    False -> buf
    True -> {
      let assert [input_area, list_area] =
        geometry.split_v(area, [geometry.Length(1), geometry.Fill])
      let buf = render_input(buf, input_area, box)
      case matches(box) {
        [] ->
          paragraph.render_styled(buf, list_area, [
            span.line_plain("No matches"),
          ])
        items -> {
          let start =
            int.max(0, box.selection.selected - list_area.size.height + 1)
          let lines =
            items
            |> list.index_map(fn(item, i) {
              let #(item, hint) = item
              let hint = " : " <> hint |> string.replace("\n", " ")
              let selected = i == box.selection.selected
              let base =
                style.default_style() |> style.with_fg(style.Rgb(111, 220, 255))
              let base = case selected {
                True -> base |> style.with_bg(style.Rgb(40, 48, 80))
                False -> base
              }
              span.line_new([
                span.span_styled(
                  case selected {
                    True -> "› "
                    False -> "  "
                  }
                    <> item,
                  base,
                ),
                span.span_styled(
                  hint,
                  style.with_fg(base, style.Rgb(210, 169, 255)),
                ),
              ])
            })
            |> list.drop(start)
          paragraph.render_styled(buf, list_area, lines)
        }
      }
    }
  }
}

fn render_input(buf, area: geometry.Rect, box: Combobox) {
  let suffix =
    string.drop_start(completion(box), string.length(box.input.value))
  let widget =
    input.input_new(case suffix {
      "" -> "Type to filter"
      _ -> ""
    })
  let buf = input.render(buf, area, widget, box.input)
  // Match the input widget's horizontal scrolling before appending ghost text.
  let start = int.max(0, box.input.cursor - area.size.width + 1)
  let hidden = text.truncate(box.input.value, start, "")
  let offset = text.cell_width(box.input.value) - text.cell_width(hidden)
  case suffix != "" && offset < area.size.width {
    False -> buf
    True ->
      span.render_line(
        buf,
        geometry.Position(area.position.x + offset, area.position.y),
        span.line_new([
          span.span_styled(
            suffix,
            style.default_style() |> style.add_modifier(style.dim()),
          ),
        ]),
        area.size.width - offset,
      )
  }
}
