import cloud/box/memory
import cloud/data/boxes.{Box}
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
  assert memory.record(memory, second)
  assert Ok(second) == memory.get(memory, "home")
  assert Error(Nil) == memory.get(memory, "other")
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
  assert memory.record(memory, Box("home", 2, root(<<"2">>)))
  assert !memory.record(memory, Box("home", 2, root(<<"3">>)))
  assert !memory.record(memory, Box("other", 2, root(<<"3">>)))
}
