import cloud/beam/execute
import cloud/data/db

/// Everything a request needs from the running system.
pub type Context {
  Context(
    db: db.Db,
    // The hub, secrets and blob store used by code running in a box.
    state: execute.State,
    policy: execute.Policy,
  )
}
