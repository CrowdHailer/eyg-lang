import cloud/beam/execute
import cloud/box/memory
import cloud/data/boxes
import cloud/data/db
import cloud/registry
import gleam/dict.{type Dict}
import overlay/llm/provider
import unixfs/check

/// Everything a request needs from the running system.
pub type Context {
  Context(
    db: db.Db,
    // The process for each box, all changes to a box are made by it.
    boxes: registry.Registry(fn(Open) -> Open),
    // Boxes no session has been made in, they are only kept in memory.
    memory: memory.Memory,
    // The process for each session, it runs one turn at a time.
    sessions: registry.Registry(fn(Nil) -> Nil),
    // The hub, secrets and blob store used by code running in a box.
    state: execute.State,
    // The source of the policy for code run in sessions, each turn records the policy it ran with.
    policy: String,
    // The llms a session can chat with, by name. There are no accounts yet so every session can use them.
    llms: Dict(String, provider.Llm),
  )
}

/// A box as its process holds it.
/// The index of the modules is only kept in memory, the first change after the process starts checks every module.
pub type Open {
  Open(box: boxes.Box, index: check.Index)
}
