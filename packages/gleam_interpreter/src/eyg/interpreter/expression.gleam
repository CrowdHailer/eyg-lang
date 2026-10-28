import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/process
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/list
import gleam/option.{None, Some}

/// Resume the interpretation loop with a value from a previous break position.
/// This can be used to resume after any break but is normally used to implement
/// effects and reference lookup
pub fn resume(
  value: state.Value(m),
  env: state.Env(m),
  k: state.Stack(m),
) -> Result(state.Value(m), state.Debug(m)) {
  case k {
    state.Empty -> Ok(value)
    state.Stack(_, meta, _) -> finish(process.resume(value, env, k, meta), meta)
  }
}

fn finish(task, meta) {
  case process.bounded(task) {
    Ok(#(Some(value), _)) -> Ok(value)
    Ok(#(None, scope)) ->
      Error(#(break.Vacant, meta, builtin.default(scope), state.Empty))
    Error(debug) -> Error(debug)
  }
}

/// Execute an expression within a scope
pub fn execute(
  exp: ir.Node(t),
  scope: state.Scope(t),
) -> Result(state.Value(t), state.Debug(t)) {
  finish(process.start(exp, scope), exp.1)
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
  resume(f, env, k)
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
