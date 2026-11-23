import cloud/beam/execute
import cloud/box
import cloud/data/journal
import cloud/file_system
import cloud/helpers
import gleam/dict
import gleam/option.{None, Some}
import gleam/string

pub fn merge_changes_from_the_same_base_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let change = fn(path, contents) {
    let assert Ok(Ok(root)) =
      execute.files(file_system.write(home.root, path, contents), context.state)
    box.merge(context, home.id, home.root, root)
  }
  let assert Ok(_) = change("/a.txt", <<"a">>)
  let assert Ok(merged) = change("/b.txt", <<"b">>)
  let assert Ok(Ok([#("a.txt", _), #("b.txt", _), #("skills", _)])) =
    execute.files(file_system.read_directory(merged.root, "/"), context.state)
  // The same change again is not a conflict, a different one is.
  let assert Ok(_) = change("/a.txt", <<"a">>)
  let assert Error(box.Conflict(["/a.txt"])) = change("/a.txt", <<"other">>)
}

pub fn type_check_the_merged_root_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let write = fn(base, path, code) {
    let assert Ok(Ok(root)) =
      execute.files(file_system.write(base, path, <<code:utf8>>), context.state)
    box.merge(context, home.id, base, root)
  }
  let assert Ok(start) = write(home.root, "/one.eyg", "1")
  let assert Ok(_) =
    write(start.root, "/two.eyg", "!int_add(1, import \"./one.eyg\")")
  // Valid from its base, but not merged with the change above.
  let assert Error(box.Invalid([error])) =
    write(start.root, "/one.eyg", "\"one\"")
  assert string.starts_with(error, "/two.eyg: ")
}

// A query that fails, as the shell is missing.
fn failing() {
  journal.append("missing", "missing", journal.Row(1, None, "{}"))
}

pub fn a_change_is_recorded_with_what_became_of_it_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let write = fn(base, path, code) {
    let assert Ok(Ok(root)) =
      execute.files(file_system.write(base, path, <<code:utf8>>), context.state)
    root
  }
  // If what became of the change cannot be recorded the box does not change.
  let root = write(home.root, "/a.txt", "a")
  let assert Error(box.Failed(_)) =
    box.merge_with(context, home.id, home.root, root, fn(_) { [failing()] })
  assert Ok(home) == box.latest(context, home.id)
  // The record is given the box after the change, or the box that refused it.
  let assert Ok(box.Accepted(changed)) =
    box.merge_with(context, home.id, home.root, root, fn(merged) {
      let assert box.Accepted(after) = merged
      assert after.sequence == 2
      []
    })
  let invalid = write(changed.root, "/bad.eyg", "!int_add(1, \"two\")")
  let assert Ok(box.Refused(box.Invalid(_), _)) =
    box.merge_with(context, home.id, changed.root, invalid, fn(merged) {
      let assert box.Refused(box.Invalid(_), refused) = merged
      assert refused == changed
      []
    })
  // A refused change is recorded too, failing to record it is a failure.
  let assert Error(box.Failed(_)) =
    box.merge_with(context, home.id, changed.root, invalid, fn(_) {
      [failing()]
    })
}

pub fn clones_copy_secrets_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Ok(Nil) = box.set_secret(context, home.id, "KEY", "home")
  let assert Ok(copy) = box.clone(context, home, None)
  assert Ok(dict.from_list([#("KEY", "home")])) == box.secrets(context, copy.id)
  // The boxes keep their own secrets.
  let assert Ok(Nil) = box.set_secret(context, copy.id, "KEY", "copy")
  assert Ok(dict.from_list([#("KEY", "home")])) == box.secrets(context, home.id)
  let assert Ok(Nil) = box.delete_secret(context, home.id, "KEY")
  assert Ok(dict.new()) == box.secrets(context, home.id)
  assert Error(box.Missing) == box.set_secret(context, "gone", "KEY", "x")
}
