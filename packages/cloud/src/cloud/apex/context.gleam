import cloud/beam/execute
import cloud/box/memory

/// Everything a request needs from the running system.
pub type Context {
  Context(
    // The boxes, they are only kept in memory.
    memory: memory.Memory,
    // The hub, secrets and blob store used by code running in a box.
    state: execute.State,
    policy: execute.Policy,
  )
}
