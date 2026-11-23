import cloud/beam/execute
import cloud/data/boxes
import cloud/data/db
import cloud/registry
import unixfs/check

/// Everything a request needs from the running system.
pub type Context {
  Context(
    db: db.Db,
    // The process for each box, all changes to a box are made by it.
    boxes: registry.Registry(fn(Open) -> Open),
    // The hub, secrets and blob store used by code running in a box.
    state: execute.State,
    policy: execute.Policy,
  )
}

/// A box as its process holds it.
/// The index of the modules is only kept in memory, the first change after the process starts checks every module.
pub type Open {
  Open(box: boxes.Box, index: check.Index)
}
