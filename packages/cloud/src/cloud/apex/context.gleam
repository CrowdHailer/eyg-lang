import cloud/beam/execute
import cloud/box/memory
import cloud/data/boxes
import cloud/data/db
import cloud/registry

/// Everything a request needs from the running system.
pub type Context {
  Context(
    db: db.Db,
    // The process for each box, it merges every change to the box.
    boxes: registry.Registry(fn(boxes.Box) -> boxes.Box),
    // Boxes no session has been made in, they are only kept in memory.
    memory: memory.Memory,
    // The hub, secrets and blob store used by code running in a box.
    state: execute.State,
    policy: execute.Policy,
  )
}
