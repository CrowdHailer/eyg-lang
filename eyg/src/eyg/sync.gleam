import eyg/analysis/inference/levels_j/contextual
import eyg/runtime/break
import eyg/runtime/interpreter/state
import gleam/dict
import harness/ffi/core

// 1. Pull packages
// 2. Edit code
// 3 publish code
// TODO remove fragment
// TODO remove packages
// analysis context is env and bindings
// continuations to solve colouring
// Break should have undefined as an error that has each of Builtin/Named/Hash/Var
// catalogue/index for all named references
// remove document and sections

// List of changes to releases makes the catalog

// remotes can resolve references
// a remote can be the file system

// cache is mutable and best represented as an actor it's state is probably best not saved in snippets

// eyg/website/run should move to a general interpreter

// fetching a hash that then relies on another hash should be tested

// Editor currently throws away block error

// Doesn't work to externalise lookup from type checking because we don't have tail recursive implementation
// eval and then turn into type

// pub fn infer(source, env, eff) {
//   contextual.do_infer(source, env, eff, refs: dict.new(), level, bindings)
// }

// snippet.set_references recomputes regardless

// What should happend for local references
// evalling dependencies can find everything a priori
// typechecking is interesting

// The snippet should turn the runtime env into the tenv only once
// Need to separate the env_to_env from projection based part of analysis -> maybe call it hints/suggestions

// I don't think we need bindings in env_to_tenv but the current function takes them and I can't prove otherwise
pub fn analyse(source) {
  todo
}

pub fn fetch() {
  // return result and tasks
  todo
}
