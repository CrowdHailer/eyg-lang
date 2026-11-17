import cloud/apex/context.{Context}
import cloud/beam/execute
import cloud/box
import cloud/box/memory
import cloud/data/boxes
import cloud/data/db
import cloud/file_system
import cloud/helpers
import gleam/string
import pog

pub fn merge_changes_from_the_same_base_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, "home")
  let change = fn(path, contents) {
    let assert Ok(Ok(root)) =
      execute.files(file_system.write(home.root, path, contents), context.state)
    box.merge(context, "home", home.root, root)
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
  let assert Ok(home) = box.create(context, "home")
  let write = fn(base, path, code) {
    let assert Ok(Ok(root)) =
      execute.files(file_system.write(base, path, <<code:utf8>>), context.state)
    box.merge(context, "home", base, root)
  }
  let assert Ok(start) = write(home.root, "/one.eyg", "1")
  let assert Ok(_) =
    write(start.root, "/two.eyg", "!int_add(1, import \"./one.eyg\")")
  // Valid from its base, but not merged with the change above.
  let assert Error(box.Invalid([error])) =
    write(start.root, "/one.eyg", "\"one\"")
  assert string.starts_with(error, "/two.eyg: ")
}

pub fn keep_a_box_in_memory_until_a_session_is_made_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, "home")
  let assert Ok(changed) =
    box.change(context, "home", file_system.write(_, "/a.txt", <<"a">>))
  // Nothing is in Postgres.
  let assert Ok(pog.Returned(rows: [], ..)) =
    db.execute(boxes.latest("home"), context.db)
  let assert Error(box.Taken) = box.create(context, "home")
  // A service started again has its own memory, so the box is lost.
  let assert Ok(memory) = memory.start()
  let restarted = Context(..context, memory: memory.data)
  let assert Error(box.Missing) = box.latest(restarted, "home")

  // The first session makes the box durable, with every event it had in memory.
  let assert Ok(Nil) = box.durable(context, "home")
  assert Ok(changed) == box.latest(restarted, "home")
  assert home.root != changed.root
  let assert Ok(Nil) = box.durable(context, "home")
  let assert Error(box.Taken) = box.create(restarted, "home")
}
