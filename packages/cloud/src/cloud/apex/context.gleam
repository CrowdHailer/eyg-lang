import cloud/beam/execute
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
    // The process for each shell, it runs one turn at a time.
    shells: registry.Registry(fn(Nil) -> Nil),
    // The process for each chat, it replies to one message at a time.
    chats: registry.Registry(fn(Nil) -> Nil),
    // The hub, secrets and blob store used by code running in a box.
    state: execute.State,
    // The source of the policy for code run in shells, each turn records the policy it ran with.
    policy: String,
    // The llms a chat can be with, by name. There are no accounts yet so every chat can use them.
    llms: Dict(String, provider.Llm),
  )
}

/// A box as its process holds it.
/// The index of the modules is only kept in memory, the first change after the process starts checks every module.
pub type Open {
  Open(box: boxes.Box, index: check.Index)
}
