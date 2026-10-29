import eyg/cli/tui/files
import eyg/cli/tui/helpers as h
import eyg/cli/tui/state
import eyg/ir/tree as ir
import gleam/list
import gleam/option.{Some}
import loam/sandbox
import morph/buffer

fn project() {
  sandbox.sandbox()
  |> sandbox.with_cwd("/project")
  |> sandbox.with_files([
    #("/project/lib/answer.eyg", "42"),
    #("/project/lib/other.eyg", "0"),
    #("/project/main.eyg", "1"),
    #("/project/.hidden.eyg", "2"),
  ])
}

pub fn completion_lists_directories_then_inserts_a_file_test() {
  let initial = state.init([], h.execute_state())
  let assert #(state, [listing]) = h.key(initial, "q")
  let #(state, sandbox) = h.drain(state, [listing], project())
  let assert state.PickImport(box:, ..) = state.mode
  assert [#("lib/", "directory"), #("main.eyg", "file")] == box.items
  let assert #(state, []) = h.paste(state, "l")
  let assert #(state, [listing]) = h.key(state, "tab")
  let #(state, sandbox) = h.drain(state, [listing], sandbox)
  let assert state.PickImport(box:, listed: "lib/", ..) = state.mode
  assert "lib/" == box.input.value
  // Browsing completions has not edited or type-checked an import.
  assert buffer.source(initial.buffer) == buffer.source(state.buffer)
  let assert #(state, []) = h.paste(state, "a")
  let assert #(state, []) = h.key(state, "tab")
  let assert #(state, [read]) = h.key(state, "enter")
  assert ir.relative("lib/answer.eyg")
    == ir.clear_annotation(buffer.source(state.buffer))
  let #(state, _) = h.drain(state, [read], sandbox)
  assert "✔  · Integer" == h.status_text(state)
}

pub fn hidden_entries_appear_when_a_dot_is_typed_test() {
  let assert #(state, [listing]) = h.key(state.init([], h.execute_state()), "q")
  let #(state, _) = h.drain(state, [listing], project())
  let assert #(state, []) = h.paste(state, ".")
  let assert state.PickImport(box:, ..) = state.mode
  assert list.contains(box.items, #(".hidden.eyg", "file"))
  let assert #(state, []) = h.key(state, "tab")
  let assert state.PickImport(box:, ..) = state.mode
  assert ".hidden.eyg" == box.input.value
}

pub fn directory_prefix_preserves_relative_and_absolute_paths_test() {
  assert "" == files.directory("answer.eyg")
  assert "../lib/" == files.directory("../lib/ans")
  assert "/project/lib/" == files.directory("/project/lib/")
}

pub fn directories_are_rejected_and_cancel_preserves_the_draft_test() {
  let initial = state.init([], h.execute_state()) |> h.with_code("42")
  let #(state, _) = h.key(initial, "q")
  let #(state, _) = h.paste(state, "lib/")
  let assert #(state, []) = h.key(state, "enter")
  let assert state.PickImport(..) = state.mode
  assert Some("Choose a file to import") == state.message
  let assert #(state, []) = h.key(state, "esc")
  assert state.Navigating == state.mode
  assert initial.buffer == state.buffer
}

pub fn stale_directory_listings_do_not_replace_current_choices_test() {
  let assert #(state, [root]) = h.key(state.init([], h.execute_state()), "q")
  let assert #(state, [nested]) = h.paste(state, "lib/")
  let #(state, sandbox) = h.drain(state, [nested], project())
  let assert state.PickImport(box: before, ..) = state.mode
  let #(state, _) = h.drain(state, [root], sandbox)
  let assert state.PickImport(box: after, listed: "lib/", ..) = state.mode
  assert before.items == after.items
}

pub fn a_path_can_be_inserted_without_available_suggestions_test() {
  let assert #(state, [root]) = h.key(state.init([], h.execute_state()), "q")
  let assert #(state, [nested]) = h.paste(state, "missing/file.eyg")
  let #(state, sandbox) = h.drain(state, [root, nested], project())
  let assert state.PickImport(box:, ..) = state.mode
  assert [] == box.items
  let assert #(state, [read]) = h.key(state, "enter")
  assert state.Navigating == state.mode
  let #(state, _) = h.drain(state, [read], sandbox)
  assert "!1 · missing reference missing/file.eyg" == h.status_text(state)
}
