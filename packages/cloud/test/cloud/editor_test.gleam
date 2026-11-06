import cloud/editor.{Edited, Run}
import gleam/list
import gleam/option.{Some}
import morph/editable as e

fn keys(edited, keys) {
  list.fold(keys, edited, fn(edited, key) {
    let assert Edited(edited) = editor.key(edited, key)
    edited
  })
}

pub fn insert_integer_test() {
  let edited = editor.new() |> keys(["n", "7", "enter"])
  assert editor.expression(edited) == e.Integer(7)
  assert editor.key(edited, "enter") == Run(e.Integer(7))
}

pub fn invalid_integer_keeps_dialog_test() {
  let edited = editor.new() |> keys(["n", "x", "enter"])
  let assert editor.EnterInteger(..) = edited.mode
  let assert Some(_) = edited.message
}

pub fn insert_string_test() {
  let edited = editor.new() |> keys(["s", "h", "i", "enter"])
  assert editor.expression(edited) == e.String("hi")
}

pub fn escape_cancels_dialog_test() {
  let edited = editor.new() |> keys(["s", "h", "esc"])
  assert edited.mode == editor.Navigating
  assert editor.is_empty(edited)
}

pub fn assign_with_picker_test() {
  let edited = editor.new() |> keys(["n", "1", "enter", "e", "x", "enter"])
  let assert e.Block([#(e.Bind("x"), e.Integer(1))], e.Vacant, _) =
    editor.expression(edited)
}

pub fn paste_into_selection_test() {
  let edited = editor.paste(editor.new(), "!int_add(1, 2)")
  let assert e.Call(_, [e.Integer(1), e.Integer(2)]) = editor.expression(edited)
}

pub fn undo_test() {
  let edited = editor.new() |> keys(["n", "1", "enter", "z"])
  assert editor.is_empty(edited)
}

pub fn unknown_key_shows_message_test() {
  let edited = editor.new() |> keys(["%"])
  let assert Some(_) = edited.message
}

pub fn check_reports_type_test() {
  let edited = editor.new() |> keys(["n", "1", "enter"])
  let edited = editor.check(edited, [], editor.without_references)
  let assert Some(_) = edited.buffer.analysis
}
