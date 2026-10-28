import glasshouse/diff.{Delete, Insert, Keep}
import gleam/list
import gleam/string

pub fn identical_texts_test() {
  assert diff.lines("a\nb\n", "a\nb\n") == [Keep("a"), Keep("b")]
}

pub fn empty_texts_test() {
  assert diff.lines("", "") == []
  assert diff.lines("", "a\n") == [Insert("a")]
  assert diff.lines("a\n", "") == [Delete("a")]
}

pub fn changed_line_test() {
  assert diff.lines("a\nb\nc\n", "a\nB\nc\n")
    == [Keep("a"), Delete("b"), Insert("B"), Keep("c")]
}

pub fn insert_and_delete_test() {
  assert diff.lines("a\nb\nc\n", "b\nc\nd\n")
    == [Delete("a"), Keep("b"), Keep("c"), Insert("d")]
}

pub fn minimal_edit_test() {
  // A B C A B B A -> C B A B A C, the example from Myers' paper, has 5 edits.
  let old = ["A", "B", "C", "A", "B", "B", "A"]
  let new = ["C", "B", "A", "B", "A", "C"]
  let edits = diff.edits(old, new)
  let #(added, removed) = diff.stats(edits)
  assert added + removed == 5
  assert apply(edits) == new
  assert original(edits) == old
}

pub fn edits_reconstruct_both_texts_test() {
  let old = string.split("the quick brown fox jumps over the lazy dog", " ")
  let new = string.split("the slow brown dog jumps over the quick fox", " ")
  let edits = diff.edits(old, new)
  assert apply(edits) == new
  assert original(edits) == old
}

fn apply(edits) {
  list.filter_map(edits, fn(edit) {
    case edit {
      Keep(line) | Insert(line) -> Ok(line)
      Delete(_) -> Error(Nil)
    }
  })
}

fn original(edits) {
  list.filter_map(edits, fn(edit) {
    case edit {
      Keep(line) | Delete(line) -> Ok(line)
      Insert(_) -> Error(Nil)
    }
  })
}

pub fn unified_diff_test() {
  let old = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n"
  let new = "one\n2\nthree\nfour\nfive\nsix\nseven\neight\nnine\n"
  assert diff.unified(old, new, 1)
    == "@@ -1,3 +1,3 @@\n one\n-two\n+2\n three\n@@ -8 +8,2 @@\n eight\n+nine"
}

pub fn nearby_changes_share_a_hunk_test() {
  let old = "a\nb\nc\nd\n"
  let new = "A\nb\nc\nD\n"
  assert list.length(diff.hunks(diff.lines(old, new), 2)) == 1
}

pub fn added_file_hunk_starts_at_zero_test() {
  assert diff.unified("", "new\n", 3) == "@@ -0,0 +1 @@\n+new"
}
