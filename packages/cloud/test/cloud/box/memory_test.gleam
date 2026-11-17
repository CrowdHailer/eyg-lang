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
  let first = Box("home", 1, root(<<"1">>))
  let second = Box("home", 2, root(<<"2">>))
  assert memory.add(memory, first)
  assert memory.record(memory, second, Some("change"))
  assert Ok(second) == memory.get(memory, "home")
  assert Error(Nil) == memory.get(memory, "other")
  assert memory.merged(memory, "home", "change")
  assert !memory.merged(memory, "home", "other")
}

pub fn name_is_kept_once_test() {
  let assert Ok(memory) = memory.start()
  let memory = memory.data
  assert memory.add(memory, Box("home", 1, root(<<"1">>)))
  assert !memory.add(memory, Box("home", 1, root(<<"2">>)))
}

pub fn sequence_is_recorded_once_test() {
  let assert Ok(memory) = memory.start()
  let memory = memory.data
  assert memory.add(memory, Box("home", 1, root(<<"1">>)))
  assert memory.record(memory, Box("home", 2, root(<<"2">>)), None)
  assert !memory.record(memory, Box("home", 2, root(<<"3">>)), None)
  assert !memory.record(memory, Box("other", 2, root(<<"3">>)), None)
}
