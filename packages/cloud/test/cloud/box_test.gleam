import cloud/beam/execute
import cloud/box
import cloud/file_system
import cloud/helpers
import gleam/option.{Some}
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
  let assert Ok(Ok([#("a.txt", _), #("b.txt", _)])) =
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
