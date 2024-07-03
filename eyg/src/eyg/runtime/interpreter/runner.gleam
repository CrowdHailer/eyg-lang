import eyg/runtime/break
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/list

// loop and eval go to runner as you'd build a new one
pub fn execute(exp, env, h) {
  loop(state.step(state.E(exp), env, state.Empty(h)))
}

pub fn resume(f, args, env, h) {
  let k =
    list.fold_right(args, state.Empty(h), fn(k, arg) {
      let #(value, meta) = arg
      state.Stack(state.CallWith(value, env), meta, k)
    })
  loop(state.step(state.V(f), env, k))
}

pub fn loop(next) {
  case next {
    state.Loop(c, e, k) -> loop(state.step(c, e, k))
    state.Break(result) -> result
  }
}

// Solves the situation that JavaScript suffers from coloured functions
// To eval code that may be async needs to return a promise of a result
pub fn await(ret) {
  case ret {
    Error(#(break.UnhandledEffect("Await", v.Promise(p)), meta, env, k)) -> {
      use return <- promise.await(p)
      await(loop(state.step(state.V(return), env, k)))
    }
    other -> promise.resolve(other)
  }
}
