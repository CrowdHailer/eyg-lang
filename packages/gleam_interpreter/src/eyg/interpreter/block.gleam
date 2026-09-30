import eyg/interpreter/builtin
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/list
import gleam/option.{type Option, None, Some}

fn loop(c, env: state.Env(t), k) {
  case c, k {
    state.E(#(ir.Vacant, _)), state.Empty -> Ok(#(None, env.scope))
    _, _ ->
      case state.step(c, env, k) {
        state.Loop(c, env, k) -> loop(c, env, k)
        state.Break(Ok(value)) -> Ok(#(Some(value), env.scope))
        state.Break(Error(reason)) -> Error(reason)
      }
  }
}

/// Execute a block of code.
/// If there is no final expression no value is returned.
/// 
/// On success the block's scope is returned for use in REPLs.
pub fn execute(
  exp: ir.Node(t),
  scope: state.Scope(t),
) -> Result(#(Option(state.Value(t)), state.Scope(t)), state.Debug(t)) {
  loop(state.E(exp), builtin.default(scope), state.Empty)
}

/// Call an evaluated function with arguments 
pub fn call(f, args, env) {
  let k =
    list.fold_right(args, state.Empty, fn(k, arg) {
      let #(value, meta) = arg
      state.Stack(state.CallWith(value, env), meta, k)
    })
  loop(state.V(f), env, k)
}

/// Resume the interpretation loop with a value from a previous break position.
/// This can be used to resume after any break but is normally used to implement
/// effects and reference lookup
pub fn resume(
  value: state.Value(t),
  env: state.Env(t),
  k: state.Stack(t),
) -> Result(#(Option(state.Value(t)), state.Scope(t)), state.Debug(t)) {
  loop(state.V(value), env, k)
}
