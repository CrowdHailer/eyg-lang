//// Multi-line text input for a terminal, on etui's textarea.
////
//// Keys are named as etui names them, with `ctrl+`, `alt+` or `shift+` in front.
//// Arrows, home and end move, with ctrl or alt arrows move by word and ctrl home and end go to the start or end.
//// Backspace and delete remove a character, with ctrl or alt a word, ctrl+u and ctrl+k to the start or end of the line.
//// Shift and enter starts a new line, shift with a motion moves the same as without it.
//// Lines are wrapped to the width they are drawn in and coloured by a highlighter.

import etui/span
import etui/style
import etui/text
import etui/widgets/textarea as ta
import gleam/int
import gleam/list
import gleam/string

pub type Textarea =
  ta.TextAreaState

pub fn new() -> Textarea {
  ta.state_new()
}

/// The text with the cursor at the end.
pub fn from_string(text: String) -> Textarea {
  ta.state_from_string(text)
}

pub fn value(state: Textarea) -> String {
  ta.value(state)
}

pub fn is_empty(state: Textarea) -> Bool {
  string.trim(value(state)) == ""
}

/// Apply a key, an error if the key does not edit or move in text.
pub fn key(state: Textarea, key: String) -> Result(Textarea, Nil) {
  let key = case key {
    "shift+enter" -> key
    "shift+" <> key -> key
    _ -> key
  }
  case key {
    "left" -> Ok(ta.move_cursor_left(state))
    "right" -> Ok(ta.move_cursor_right(state))
    "up" -> Ok(ta.move_cursor_up(state))
    "down" -> Ok(ta.move_cursor_down(state))
    "home" -> Ok(ta.move_to_line_start(state))
    "end" -> Ok(ta.move_to_line_end(state))
    "ctrl+home" -> Ok(ta.TextAreaState(..state, cursor_x: 0, cursor_y: 0))
    "ctrl+end" -> Ok(from_string(value(state)))
    "ctrl+left" | "alt+left" -> Ok(edit(state, word_left))
    "ctrl+right" | "alt+right" -> Ok(edit(state, word_right))
    "backspace" -> Ok(ta.backspace(state))
    "delete" -> Ok(edit(state, delete_forward))
    "ctrl+backspace" | "alt+backspace" | "ctrl+w" ->
      Ok(edit(state, fn(c) { Cursor(..c, before: drop_word(c.before)) }))
    "ctrl+delete" | "alt+delete" ->
      Ok(edit(state, fn(c) { Cursor(..c, after: skip_word(c.after)) }))
    "ctrl+u" -> Ok(edit(state, fn(c) { Cursor(..c, before: "") }))
    "ctrl+k" -> Ok(ta.delete_to_line_end(state))
    "shift+enter" -> Ok(insert(state, "\n"))
    _ ->
      case string.length(key) {
        1 -> Ok(insert(state, key))
        _ -> Error(Nil)
      }
  }
}

/// Insert text at the cursor, newlines in it start new lines.
pub fn insert(state: Textarea, inserted: String) -> Textarea {
  let inserted = string.replace(inserted, "\r\n", "\n")
  use cursor <- edit(state)
  case string.split(cursor.before <> inserted, "\n") |> list.reverse {
    [last, ..lines] ->
      Cursor(
        ..cursor,
        above: list.append(cursor.above, list.reverse(lines)),
        before: last,
      )
    [] -> cursor
  }
}

// The text around the cursor: whole lines above and below it, and its line either side of it.
type Cursor {
  Cursor(
    above: List(String),
    before: String,
    after: String,
    below: List(String),
  )
}

fn edit(state: Textarea, change: fn(Cursor) -> Cursor) -> Textarea {
  let #(above, rest) = list.split(state.lines, state.cursor_y)
  let #(line, below) = case rest {
    [line, ..below] -> #(line, below)
    [] -> #("", [])
  }
  let before = text.truncate(line, state.cursor_x, "")
  let after = text.drop_graphemes(line, list.length(text.graphemes(before)))
  let Cursor(above:, before:, after:, below:) =
    change(Cursor(above, before, after, below))
  ta.TextAreaState(
    lines: list.flatten([above, [before <> after], below]),
    cursor_x: text.cell_width(before),
    cursor_y: list.length(above),
  )
}

// At the start of a line a word motion carries on in the line before.
fn word_left(cursor: Cursor) {
  case cursor.before, list.reverse(cursor.above) {
    "", [] -> cursor
    "", [previous, ..above] ->
      Cursor(above: list.reverse(above), before: previous, after: "", below: [
        cursor.after,
        ..cursor.below
      ])
      |> word_left
    before, _ -> {
      let kept = drop_word(before)
      let moved = string.drop_start(before, string.length(kept))
      Cursor(..cursor, before: kept, after: moved <> cursor.after)
    }
  }
}

// At the end of a line a word motion carries on in the next line.
fn word_right(cursor: Cursor) {
  case cursor.after, cursor.below {
    "", [] -> cursor
    "", [next, ..below] ->
      Cursor(
        above: list.append(cursor.above, [cursor.before]),
        before: "",
        after: next,
        below:,
      )
      |> word_right
    after, _ -> {
      let rest = skip_word(after)
      let moved = string.drop_end(after, string.length(rest))
      Cursor(..cursor, before: cursor.before <> moved, after: rest)
    }
  }
}

fn delete_forward(cursor: Cursor) {
  case string.pop_grapheme(cursor.after), cursor.below {
    Ok(#(_, after)), _ -> Cursor(..cursor, after:)
    Error(Nil), [next, ..below] -> Cursor(..cursor, after: next, below:)
    Error(Nil), [] -> cursor
  }
}

// The text without the word at its end, and any spaces or punctuation after that word.
fn drop_word(text: String) -> String {
  string.to_graphemes(text)
  |> list.reverse
  |> list.drop_while(fn(g) { !word(g) })
  |> list.drop_while(word)
  |> list.reverse
  |> string.concat
}

// The text after the word at its start, and any spaces or punctuation before that word.
fn skip_word(text: String) -> String {
  string.to_graphemes(text)
  |> list.drop_while(fn(g) { !word(g) })
  |> list.drop_while(word)
  |> string.concat
}

// Letters, digits and underscores are part of a word.
fn word(grapheme: String) -> Bool {
  grapheme == "_"
  || string.contains("0123456789", grapheme)
  || string.lowercase(grapheme) != string.uppercase(grapheme)
}

/// The lines of text as they are drawn `width` cells wide, and the row the cursor is on.
/// `highlight` colours the whole text, giving spans for each of its lines.
/// The cursor is drawn when the text is `active`.
pub fn lines(
  state: Textarea,
  highlight: fn(String) -> List(List(span.Span)),
  width: Int,
  active: Bool,
) -> #(List(span.Line), Int) {
  let width = int.max(1, width)
  let highlighted = highlight(value(state))
  let rows =
    list.index_map(highlighted, fn(spans, y) {
      let spans = case active && y == state.cursor_y {
        True -> with_cursor(spans, state.cursor_x)
        False -> spans
      }
      wrap(spans, width)
    })
  let cursor_row =
    list.take(rows, state.cursor_y)
    |> list.map(list.length)
    |> int.sum
    |> int.add(state.cursor_x / width)
  #(list.flatten(rows), cursor_row)
}

// Reverse the cell at the cursor, a space after the end of the line.
fn with_cursor(spans: List(span.Span), x: Int) -> List(span.Span) {
  let cells = cells(spans)
  let #(before, at) = list.split(cells, x)
  let #(cursor, after) = case at {
    [#(g, style), ..after] -> #(
      #(g, style.add_modifier(style, style.reverse())),
      after,
    )
    [] -> #(#(" ", style.reversed()), [])
  }
  join(list.flatten([before, [cursor], after]))
}

// The graphemes of spans with their style, a wide grapheme is followed by an empty cell.
fn cells(spans: List(span.Span)) {
  list.flat_map(spans, fn(span) {
    text.graphemes(span.content)
    |> list.flat_map(fn(g) {
      case text.grapheme_cell_width(g) {
        2 -> [#(g, span.style), #("", span.style)]
        _ -> [#(g, span.style)]
      }
    })
  })
}

fn join(cells) -> List(span.Span) {
  list.fold(cells, [], fn(spans, cell) {
    let #(g, style) = cell
    case spans {
      [span.Span(content:, style: previous, ..), ..rest] if previous == style -> [
        span.span_styled(content <> g, style),
        ..rest
      ]
      _ -> [span.span_styled(g, style), ..spans]
    }
  })
  |> list.reverse
}

fn wrap(spans, width) -> List(span.Line) {
  case cells(spans) {
    [] -> [span.line_new([])]
    cells ->
      list.sized_chunk(cells, width)
      |> list.map(fn(row) { span.line_new(join(row)) })
  }
}

/// Text without highlighting.
pub fn plain(text: String) -> List(List(span.Span)) {
  string.split(text, "\n") |> list.map(fn(line) { [span.span_plain(line)] })
}
