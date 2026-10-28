import gleam/list
import loam/internal/prompt_editor as editor

fn edit(keys, history) {
  list.fold(keys, editor.new(history), fn(model, key) {
    let assert editor.Continue(model) = editor.update(model, key)
    model
  })
}

pub fn cursor_insert_delete_home_and_end_test() {
  let model =
    edit(
      ["a", "b", "c", "ArrowLeft", "Backspace", "x", "Home", "Delete", "End"],
      [],
    )
  assert editor.update(model, "Enter") == editor.Submit("xc")
}

pub fn combining_and_wide_characters_are_edited_as_graphemes_test() {
  let model = edit(["e", "\u{301}", "🌱", "ArrowLeft", "Backspace"], [])
  assert editor.text(model.line) == "🌱"
  let model = edit(["🌱", "x", "Home", "Delete"], [])
  assert editor.text(model.line) == "x"
}

pub fn browsing_returns_to_the_unsubmitted_draft_test() {
  let model =
    edit(["d", "r", "a", "f", "t", "ArrowUp", "ArrowUp"], ["recent", "older"])
  assert editor.text(model.line) == "older"
  let assert editor.Continue(model) = editor.update(model, "ArrowDown")
  assert editor.text(model.line) == "recent"
  let assert editor.Continue(model) = editor.update(model, "ArrowDown")
  assert editor.text(model.line) == "draft"
}

pub fn control_shortcuts_and_empty_eof_test() {
  assert editor.update(editor.new([]), "\u{4}") == editor.Stop
  let model = edit(["a", "b", "c", "\u{1}", "ArrowRight", "\u{b}", "\u{5}"], [])
  assert editor.text(model.line) == "a"
  let assert editor.Continue(model) = editor.update(model, "\u{15}")
  assert editor.text(model.line) == ""
}
