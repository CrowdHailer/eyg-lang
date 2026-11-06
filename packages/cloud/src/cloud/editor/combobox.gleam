//// Editable text with suggestions, for choosing names, fields and effects.
//// Enter submits, Tab completes to the next branching point,
//// Up and Down move through the matches.
////
//// Ported from the CLI's TUI widget, rendering to lines instead of a grid.

import etui/keys
import etui/span.{type Line}
import etui/style
import etui/widgets/input
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Combobox {
  Combobox(
    items: List(#(String, String)),
    input: input.InputState,
    selected: Option(Int),
    validate: fn(String) -> Result(Nil, String),
    error: Option(String),
  )
}

pub type Action {
  Updated(Combobox)
  Selected(String)
  Cancelled
}

pub fn new(items: List(#(String, String)), value: String) -> Combobox {
  Combobox(items, input.state_from_string(value), None, fn(_) { Ok(Nil) }, None)
}

pub fn matches(box: Combobox) -> List(#(String, String)) {
  let query = string.lowercase(box.input.value)
  list.filter(box.items, fn(item) {
    string.starts_with(string.lowercase(item.0), query)
  })
}

pub fn update(box: Combobox, key: String) -> Action {
  case key {
    "esc" -> Cancelled
    "enter" -> {
      let value = case box.selected {
        Some(index) ->
          case list.drop(matches(box), index) {
            [#(item, _), ..] -> item
            [] -> box.input.value
          }
        None -> box.input.value
      }
      case box.validate(value) {
        Ok(Nil) -> Selected(value)
        Error(message) -> Updated(Combobox(..box, error: Some(message)))
      }
    }
    "tab" -> with_input(box, input.state_from_string(completion(box)))
    "up" -> {
      let selected = case box.selected {
        Some(index) -> Some(int.max(index - 1, 0))
        None -> Some(0)
      }
      Updated(Combobox(..box, selected:))
    }
    "down" -> {
      let last = list.length(matches(box)) - 1
      let selected = case box.selected {
        Some(index) -> Some(int.min(index + 1, int.max(last, 0)))
        None -> Some(0)
      }
      Updated(Combobox(..box, selected:))
    }
    _ -> with_input(box, edit_input(box.input, key))
  }
}

pub fn paste(box: Combobox, text: String) -> Combobox {
  let edited = insert_text(box.input, text)
  Combobox(..box, input: edited, selected: None, error: None)
}

/// Insert text at the caret, flattened to one line.
pub fn insert_text(
  editing: input.InputState,
  text: String,
) -> input.InputState {
  text
  |> string.replace("\r", "")
  |> string.replace("\n", " ")
  |> string.to_graphemes
  |> list.fold(editing, fn(editing, char) {
    input.insert_char(input.input_new(""), editing, char)
  })
}

/// Field editing shared by every text input.
pub fn edit_input(editing: input.InputState, key: String) -> input.InputState {
  case key {
    "ctrl+a" -> input.move_to_start(editing)
    "ctrl+e" -> input.move_to_end(editing)
    "ctrl+u" -> input.clear_state(editing)
    "ctrl+k" -> input.delete_to_end(editing)
    _ ->
      case keys.parse(key) {
        keys.KeyEvent(code, keys.Modifiers(ctrl: False, alt: False, ..)) ->
          case code {
            keys.Char(char) ->
              input.insert_char(input.input_new(""), editing, char)
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
}

fn completion(box: Combobox) -> String {
  let items = matches(box)
  let from = option.unwrap(box.selected, 0)
  case list.drop(items, from) {
    [] -> box.input.value
    [#(selected, _), ..] -> {
      let shared =
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
  case edited.value == box.input.value {
    True -> Updated(Combobox(..box, input: edited))
    False ->
      Updated(Combobox(..box, input: edited, selected: None, error: None))
  }
}

/// The input line, with the completion ghosted after the caret,
/// then any error, then up to `limit` matches.
pub fn lines(box: Combobox, limit: Int) -> List(Line) {
  let suffix =
    string.drop_start(completion(box), string.length(box.input.value))
  let field =
    span.Line(
      ..input_line(box.input),
      spans: list.append(input_line(box.input).spans, [
        span.span_styled(
          suffix,
          style.add_modifier(style.default_style(), style.dim()),
        ),
      ]),
    )
  let error = case box.error {
    Some(message) -> [
      span.line_new([
        span.span_styled(
          message,
          style.with_fg(style.default_style(), style.Indexed(1)),
        ),
      ]),
    ]
    None -> []
  }
  let items = case matches(box) {
    [] -> [
      span.line_new([
        span.span_styled(
          "no matches",
          style.add_modifier(style.default_style(), style.dim()),
        ),
      ]),
    ]
    items -> {
      let selected = option.unwrap(box.selected, -1)
      let start = int.max(0, selected - limit + 1)
      items
      |> list.index_map(fn(item, index) {
        let #(name, hint) = item
        let base = style.with_fg(style.default_style(), style.Indexed(14))
        let base = case index == selected {
          True -> style.add_modifier(base, style.reverse())
          False -> base
        }
        let marker = case index == selected {
          True -> "› "
          False -> "  "
        }
        let hint = case hint {
          "" -> []
          _ -> [
            span.span_styled(
              " : " <> string.replace(hint, "\n", " "),
              style.with_fg(style.default_style(), style.Indexed(13)),
            ),
          ]
        }
        span.line_new([span.span_styled(marker <> name, base), ..hint])
      })
      |> list.drop(start)
      |> list.take(limit)
    }
  }
  [field, ..list.append(error, items)]
}

/// A one line text field with a block cursor.
pub fn input_line(editing: input.InputState) -> Line {
  let graphemes = string.to_graphemes(editing.value)
  // The input widget counts the caret in cells; graphemes are close enough
  // for names and numbers.
  let before = list.take(graphemes, editing.cursor) |> string.concat
  let #(under, after) = case list.drop(graphemes, editing.cursor) {
    [] -> #(" ", "")
    [char, ..rest] -> #(char, string.concat(rest))
  }
  span.line_new([
    span.span_plain(before),
    span.span_styled(
      under,
      style.default_style()
        |> style.add_modifier(style.reverse())
        |> style.add_modifier(style.blink()),
    ),
    span.span_plain(after),
  ])
}
