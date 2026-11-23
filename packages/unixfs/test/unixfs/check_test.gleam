import eyg/analysis/inference/levels_j/contextual as infer
import gleam/dict
import gleam/list
import unixfs/check

// Answer every package lookup with nothing, returning the references that were looked up.
fn run(step) {
  do_run(step, [])
}

fn do_run(step, lookups) {
  case step {
    infer.Done(value) -> #(value, list.reverse(lookups))
    infer.Lookup(reference, resume) ->
      do_run(resume(Error(Nil)), [reference, ..lookups])
  }
}

fn files(files: List(#(List(String), String))) {
  list.map(files, fn(file) { #(file.0, <<file.1:utf8>>) })
}

const library = [
  #(["lib", "one.eyg"], "1"),
  #(["lib", "two.eyg"], "!int_add(import \"./one.eyg\", 1)"),
  #(["app", "main.eyg"], "!int_add(import \"../lib/two.eyg\", 1)"),
  #(["other.eyg"], "\"other\""),
  #(["notes.txt"], "notes"),
]

// Index the library, then check the files after a change from the index.
// The outcome is the same as checking the files after the change in full.
fn check_changed(after) {
  let #(#(_, index), _) = run(check.index(files(library)))
  let #(#(changed, _), lookups) = run(check.changed(index, files(after)))
  let #(full, _) = run(check.files(files(after)))
  assert changed == full
  #(changed, lookups)
}

fn replace(files, path, contents) {
  list.key_set(files, path, contents)
}

pub fn index_is_the_same_as_a_full_check_test() {
  let #(#(indexed, _), _) = run(check.index(files(library)))
  let #(full, _) = run(check.files(files(library)))
  assert indexed == full
  assert 4 == dict.size(full)
}

pub fn change_a_module_test() {
  let #(checked, _) = check_changed(replace(library, ["lib", "one.eyg"], "2"))
  assert list.all(dict.values(checked), fn(outcome) {
    case outcome {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}

pub fn changed_type_breaks_unchanged_importer_test() {
  let #(checked, _) =
    check_changed(replace(library, ["lib", "one.eyg"], "\"one\""))
  let assert Ok(Error(check.TypeErrors(_))) =
    dict.get(checked, ["lib", "two.eyg"])
}

pub fn remove_a_module_test() {
  let #(checked, _) =
    check_changed(
      list.filter(library, fn(file) { file.0 != ["lib", "one.eyg"] }),
    )
  assert Ok(Error(check.MissingModule)) == dict.get(checked, ["lib", "one.eyg"])
}

pub fn add_a_module_test() {
  check_changed(
    list.append(library, [#(["new.eyg"], "import \"./other.eyg\"")]),
  )
}

pub fn import_a_file_that_is_not_a_module_test() {
  check_changed(replace(library, ["other.eyg"], "import \"./notes.txt\""))
}

pub fn stop_importing_a_file_that_is_not_a_module_test() {
  let library =
    replace(library, ["other.eyg"], "let _ = import \"./data.json\"\n1")
    |> list.append([#(["data.json"], "{}")])
  let #(#(_, index), _) = run(check.index(files(library)))
  let after = files(replace(library, ["other.eyg"], "1"))
  let #(#(changed, _), _) = run(check.changed(index, after))
  let #(full, _) = run(check.files(after))
  assert changed == full
  assert Error(Nil) == dict.get(changed, ["data.json"])
}

// A module with a package reference looks it up each time it is checked.
pub fn modules_that_did_not_change_are_not_checked_again_test() {
  let library = replace(library, ["other.eyg"], "let _ = @std\n\"other\"")
  let #(#(_, index), lookups) = run(check.index(files(library)))
  assert 1 == list.length(lookups)
  // other.eyg failed to type check, as @std is not available, so it is checked again.
  let #(#(_, index), lookups) =
    run(check.changed(index, files(replace(library, ["notes.txt"], "more"))))
  assert 1 == list.length(lookups)
  let fixed = replace(library, ["other.eyg"], "\"other\"")
  let #(#(_, index), _) = run(check.changed(index, files(fixed)))
  let #(_, lookups) =
    run(check.changed(index, files(replace(fixed, ["lib", "one.eyg"], "2"))))
  assert [] == lookups
}

pub fn a_single_file_test() {
  let #(#(_, index), _) = run(check.index([#([], <<"!int_add(1, 2)":utf8>>)]))
  let changed = [#([], <<"\"two\"":utf8>>)]
  let #(#(checked, _), _) = run(check.changed(index, changed))
  let #(full, _) = run(check.files(changed))
  assert checked == full
  let assert [#([], Ok(_))] = dict.to_list(checked)
}
