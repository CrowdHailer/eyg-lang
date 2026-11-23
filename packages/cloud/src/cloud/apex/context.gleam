import cloud/beam/execute
import cloud/data/boxes
import cloud/data/db
import cloud/registry

/// Everything a request needs from the running system.
pub type Context {
  Context(
    db: db.Db,
    // The process for each box, all changes to a box are made by it.
    boxes: registry.Registry(fn(boxes.Box) -> boxes.Box),
    // The hub, secrets and blob store used by code running in a box.
    state: execute.State,
    policy: execute.Policy,
  )
}
