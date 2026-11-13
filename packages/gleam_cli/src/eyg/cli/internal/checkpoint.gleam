//// Host-owned progress retained when an execution budget interrupts a driver.

import javascript/mutable_reference as reference

pub type Checkpoint(a) =
  reference.MutableReference(a)

pub fn new(value: a) -> Checkpoint(a) {
  reference.new(value)
}

pub fn read(checkpoint: Checkpoint(a)) -> a {
  reference.get(checkpoint)
}

pub fn write(checkpoint: Checkpoint(a), value: a) -> Nil {
  let _ = reference.set(checkpoint, value)
  Nil
}
