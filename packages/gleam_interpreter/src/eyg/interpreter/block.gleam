import eyg/interpreter/builtin
import eyg/interpreter/process
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/list
import gleam/option.{type Option, Some}

fn loop(c, env: state.Env(t), k) {
  case c {
    state.Call(_, _, meta) ->
      process.from_state(c, env, k, meta) |> process.bounded
    state.E(node) -> process.start(node, env.scope) |> process.bounded
    state.V(value) ->
      case k {
        state.Stack(_, meta, _) ->
          process.resume(value, env, k, meta) |> process.bounded
        state.Empty -> Ok(#(Some(value), env.scope))
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
