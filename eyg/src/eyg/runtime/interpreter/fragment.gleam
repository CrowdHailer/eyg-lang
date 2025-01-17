// Names are hard here should I call this a module it seems weird but there is more to this than just being a small fragment
// I think module beaks fragment but I call them fragments on the DB
// component resource module pack
import eyg/runtime/break
import eyg/runtime/interpreter/state
import gleam/dict
import harness/ffi/core

// called execute to match other interpreters even though it has no effects.
// execute also stands for multiple eval/applys.
pub fn execute(source) {
  // scope always starts empty
  let scope = []
  // references will be handled externally
  let references = dict.new()
  // builtins are a fixed lot
  let builtins = core.lib().1
  let env = state.Env(scope, references, builtins)

  // modules are pure
  let handlers = dict.new()
  let k = state.Empty(handlers)
  loop(state.step(state.E(source), env, k))
}

pub fn resume(value, env, k) {
  loop(state.step(state.V(value), env, k))
}

pub type Reference {
  Hash(hash: String)
  Named
}

pub type Evaluation(m) {
  Succeeded(state.Value(m))
  Failed(state.Debug(m))
  Resolving(Reference, m, state.Env(m), state.Stack(m))
}

fn loop(next) {
  case next {
    state.Loop(c, e, k) -> loop(state.step(c, e, k))
    state.Break(Ok(value)) -> Succeeded(value)
    state.Break(Error(#(break.UndefinedReference(r), meta, e, k))) ->
      Resolving(Hash(r), meta, e, k)
    state.Break(Error(debug)) -> Failed(debug)
  }
}
