import cloud/box/memory
import cloud/data/boxes.{Box}
import gleam/option.{None, Some}
import unixfs/mfs

fn root(contents) {
  mfs.identify(mfs.File(contents)).cid
}

pub fn latest_event_is_the_box_test() {
  let assert Ok(memory) = memory.start()
  let memory = memory.data
  let first = Box("1", Some("home"), 1, root(<<"1">>))
  let second = Box("1", Some("home"), 2, root(<<"2">>))
  assert memory.add(memory, first)
  memory.record(memory, second, Some("change"))
  assert Ok(second) == memory.get(memory, "1")
  assert Error(Nil) == memory.get(memory, "2")
  assert memory.merged(memory, "1", "change")
  assert !memory.merged(memory, "1", "other")
}

pub fn name_is_kept_once_test() {
  let assert Ok(memory) = memory.start()
  let memory = memory.data
  assert memory.add(memory, Box("1", Some("home"), 1, root(<<"1">>)))
  assert !memory.add(memory, Box("2", Some("home"), 1, root(<<"2">>)))
  // Transient boxes have no name to share.
  assert memory.add(memory, Box("3", None, 1, root(<<"3">>)))
  assert memory.add(memory, Box("4", None, 1, root(<<"4">>)))
  assert [Box("1", Some("home"), 1, root(<<"1">>))] == memory.named(memory)
}
