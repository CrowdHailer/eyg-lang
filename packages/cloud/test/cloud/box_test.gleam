import cloud/apex/context.{Context}
import cloud/beam/execute
import cloud/box
import cloud/box/memory
import cloud/data/boxes
import cloud/data/db
import cloud/file_system
import cloud/helpers
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import pog

pub fn merge_changes_from_the_same_base_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let change = fn(path, contents) {
    let assert Ok(Ok(root)) =
      execute.files(file_system.write(home.root, path, contents), context.state)
    box.merge(context, home.id, home.root, root, None)
  }
  let assert Ok(_) = change("/a.txt", <<"a">>)
  let assert Ok(merged) = change("/b.txt", <<"b">>)
  let assert Ok(Ok([#("_box", _), #("a.txt", _), #("b.txt", _), #("skills", _)])) =
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
    box.merge(context, home.id, base, root, None)
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
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Ok(Ok(root)) =
    execute.files(
      file_system.write(home.root, "/a.txt", <<"a">>),
      context.state,
    )
  let assert Ok(changed) =
    box.merge(context, home.id, home.root, root, Some("change"))
  // Nothing is in Postgres, the box is listed from memory.
  let assert Ok(pog.Returned(rows: [], ..)) =
    db.execute(boxes.latest(home.id), context.db)
  let assert Ok(named) = box.named(context)
  assert list.contains(named, changed)
  let assert Error(box.Taken) = box.create(context, Some("home"))
  // A service started again has its own memory, so the box is lost.
  let assert Ok(memory) = memory.start()
  let restarted = Context(..context, memory: memory.data)
  let assert Error(box.Missing) = box.latest(restarted, home.id)

  // The first session makes the box durable, with every event it had in memory.
  let assert Ok(Nil) = box.durable(context, home.id)
  assert Ok(changed) == box.latest(restarted, home.id)
  let assert Ok(pog.Returned(rows: [saved], ..)) =
    db.execute(boxes.merged(home.id, "change"), context.db)
  assert saved == changed
  // The change it merged in memory is still only merged once.
  assert Ok(changed)
    == box.merge(context, home.id, home.root, root, Some("change"))
  let assert Ok(Nil) = box.durable(context, home.id)
  let assert Error(box.Taken) = box.create(restarted, Some("home"))
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
  // Secrets kept in memory are recorded when the box is made durable.
  let assert Ok(Nil) = box.durable(context, copy.id)
  let assert Ok(memory) = memory.start()
  let restarted = Context(..context, memory: memory.data)
  assert Ok(dict.from_list([#("KEY", "copy")]))
    == box.secrets(restarted, copy.id)
  let assert Ok(Nil) = box.set_secret(restarted, copy.id, "OTHER", "x")
  assert Ok(dict.from_list([#("KEY", "copy"), #("OTHER", "x")]))
    == box.secrets(context, copy.id)
}
