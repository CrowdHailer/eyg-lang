import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/javascript/promise
import gleam/list

/// Resume the interpretation loop with a value from a previous break position.
/// This can be used to resume after any break but is normally used to implement
/// effects and reference lookup
pub fn resume(
  value: state.Value(m),
  env: state.Env(m),
  k: state.Stack(m),
) -> Result(state.Value(m), state.Debug(m)) {
  loop(state.step(state.V(value), env, k))
}

fn loop(next) {
  case next {
    state.Loop(c, e, k) -> loop(state.step(c, e, k))
    state.Break(result) -> result
  }
}

// Solves the situation that JavaScript suffers from coloured functions
// To eval code that may be async needs to return a promise of a result
pub fn await(ret) {
  case ret {
    Error(#(break.UnhandledEffect("Await", v.Promise(p)), _meta, env, k)) -> {
      use return <- promise.await(p)
      await(loop(state.step(state.V(return), env, k)))
    }
    other -> promise.resolve(other)
  }
}

/// Execute an expression within a scope
pub fn execute(
  exp: ir.Node(t),
  scope: state.Scope(t),
) -> Result(state.Value(t), state.Debug(t)) {
  loop(state.step(state.E(exp), builtin.default(scope), state.Empty))
}

/// Call an evaluated function with a list of args
pub fn call(
  f: state.Value(t),
  args: List(#(state.Value(t), t)),
) -> Result(state.Value(t), state.Debug(t)) {
  // If f is a function, rather than builtin, it will be a closure with the environment captures
  let env = builtin.default([])

  let k =
    list.fold_right(args, state.Empty, fn(k, arg) {
      let #(value, meta) = arg
      state.Stack(state.CallWith(value, env), meta, k)
    })
  loop(state.step(state.V(f), env, k))
}

pub fn call_field(
  record: state.Value(t),
  field: String,
  meta: t,
  args: List(#(state.Value(t), t)),
) -> Result(state.Value(t), state.Debug(t)) {
  let select = v.Partial(v.Select(field), [])
  call(select, [#(record, meta), ..args])
}
