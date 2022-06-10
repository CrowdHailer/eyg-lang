import gleam/io
import eyg/editor/editor
import eyg/typer/harness

pub fn fn_equality_test() {
  assert False = fn() { Nil } == fn() { Nil }

  let f = fn() { Nil }
  assert True = f == f
}

fn empty_editor() {
  editor.init("{\"node\": \"Hole\"}", harness.Harness([], fn(_native) { todo }))
}

// TODO maybe editor should have core state and view state?
pub fn show_encoded_test() {
  let editor = empty_editor()
  assert [_] = editor.inconsistencies(editor)
  assert Error(Nil) = editor.paste(editor)
}
