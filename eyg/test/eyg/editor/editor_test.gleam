import gleam/io
import eyg/ast/expression as e
import eyg/editor/editor
import eyg/typer/harness

pub fn fn_equality_test() {
  assert False = fn() { Nil } == fn() { Nil }

  let f = fn() { Nil }
  assert True = f == f
}

fn empty_editor() {
  editor.init(
    "{\"node\": \"Tuple\", \"elements\": []}",
    harness.Harness([], fn(_native) { todo }),
  )
}

// TODO maybe editor should have core state and view state?
pub fn paste_empty_test() {
  let editor = empty_editor()
  assert Error(Nil) = editor.paste(editor)
}

pub fn increase_selection_from_nothing_test() {
  let editor = empty_editor()

  assert Error(Nil) = editor.increase_selection(editor)
}

pub fn move_test_should_change_nothing() {
  Nil
}
// Binary should be a new state that only effects afterwards
