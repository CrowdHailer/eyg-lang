//// Pure grapheme editing and per-run prompt history navigation.

import gleam/int
import gleam/list
import gleam/order
import gleam/string

pub type Line {
  Line(before: List(String), after: List(String))
}

pub type Model {
  Model(line: Line, history: List(String), browsing: Int, draft: String)
}

pub type Change {
  Continue(Model)
  Submit(String)
  Stop
}

pub fn new(history) {
  Model(Line([], []), history, 0, "")
}

pub fn text(line: Line) {
  string.concat(list.append(list.reverse(line.before), line.after))
}

pub fn update(model: Model, key: String) {
  let line = model.line
  let next = fn(line) { Continue(Model(..model, line:)) }
  case key {
    "Enter" -> Submit(text(line))
    "\u{4}" if line.before == [] && line.after == [] -> Stop
    "\u{1}" | "Home" ->
      next(Line([], list.append(list.reverse(line.before), line.after)))
    "\u{5}" | "End" ->
      next(Line(list.append(list.reverse(line.after), line.before), []))
    "\u{15}" -> next(Line([], []))
    "\u{b}" -> next(Line(line.before, []))
    "Backspace" ->
      case line.before {
        [] -> next(line)
        [_, ..before] -> next(Line(before, line.after))
      }
    "Delete" | "\u{4}" ->
      case line.after {
        [] -> next(line)
        [_, ..after] -> next(Line(line.before, after))
      }
    "ArrowLeft" ->
      case line.before {
        [] -> next(line)
        [char, ..before] -> next(Line(before, [char, ..line.after]))
      }
    "ArrowRight" ->
      case line.after {
        [] -> next(line)
        [char, ..after] -> next(Line([char, ..line.before], after))
      }
    "ArrowUp" | "ArrowDown" -> browse(model, key)
    char ->
      case string.compare(char, " "), string.length(char) {
        order.Lt, _ -> next(line)
        _, 1 -> {
          let before = case line.before {
            [] -> [char]
            [previous, ..rest] ->
              list.append(
                string.to_graphemes(previous <> char) |> list.reverse,
                rest,
              )
          }
          next(Line(before, line.after))
        }
        _, _ -> next(line)
      }
  }
}

fn browse(model: Model, key) {
  let index = case key {
    "ArrowUp" -> int.min(list.length(model.history), model.browsing + 1)
    _ -> int.max(0, model.browsing - 1)
  }
  let draft = case model.browsing {
    0 -> text(model.line)
    _ -> model.draft
  }
  let text = case index, list.drop(model.history, index - 1) {
    0, _ -> draft
    _, [text, ..] -> text
    _, _ -> draft
  }
  Continue(Model(
    Line(string.to_graphemes(text) |> list.reverse, []),
    model.history,
    index,
    draft,
  ))
}

/// Use the terminal to position the cursor, including wide and combining glyphs.
pub fn redraw(line: Line) {
  "\u{1b}8"
  <> text(line)
  <> "\u{1b}[0J\u{1b}8"
  <> string.concat(list.reverse(line.before))
}
