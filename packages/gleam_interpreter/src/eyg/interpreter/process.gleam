//// A cooperatively scheduled interpreter. A slice counts reductions, including
//// pure computations: yielding does not depend on the program performing IO.

import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/option.{type Option, None, Some}

pub const default_fuel = 1_000_000

pub opaque type Process(m) {
  Process(
    control: state.Control(m),
    env: state.Env(m),
    stack: state.Stack(m),
    location: m,
  )
}

pub type Slice(m) {
  Yielded(Process(m))
  Returned(Option(state.Value(m)), state.Scope(m))
  Interrupted(state.Debug(m))
}

pub fn start(node: ir.Node(m), scope: state.Scope(m)) -> Process(m) {
  Process(state.E(node), builtin.default(scope), state.Empty, node.1)
}

pub fn resume(
  value: state.Value(m),
  env: state.Env(m),
  stack: state.Stack(m),
  location: m,
) -> Process(m) {
  Process(state.V(value), env, stack, location)
}

pub fn slice(process: Process(m), fuel: Int) -> Slice(m) {
  let Process(control, env, stack, location) = process
  case control, stack {
    state.E(#(ir.Vacant, _)), state.Empty -> Returned(None, env.scope)
    _, _ if fuel <= 0 -> Yielded(process)
    _, _ ->
      case state.step(control, env, stack) {
        state.Loop(control, env, stack) ->
          slice(Process(control, env, stack, location), fuel - 1)
        state.Break(Ok(value)) -> Returned(Some(value), env.scope)
        state.Break(Error(debug)) -> Interrupted(debug)
      }
  }
}

/// Compatibility runner with a finite budget. Schedulers should use `slice`
/// and retain a yielded process; cancelling it simply drops the value.
pub fn bounded(
  process: Process(m),
) -> Result(#(Option(state.Value(m)), state.Scope(m)), state.Debug(m)) {
  case slice(process, default_fuel) {
    Returned(value, scope) -> Ok(#(value, scope))
    Interrupted(debug) -> Error(debug)
    Yielded(Process(_, env, stack, location)) ->
      Error(#(
        break.UnhandledEffect(
          "ExecutionLimit",
          v.String("interpreter reduction budget exhausted"),
        ),
        location,
        env,
        stack,
      ))
  }
}
