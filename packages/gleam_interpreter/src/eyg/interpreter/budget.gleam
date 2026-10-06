//// Cooperative execution for hosts that need to bound or schedule evaluation.
//// A budget counts interpreter transitions, not milliseconds or allocated bytes.
//// Individual builtins and structural comparisons can do work within one step;
//// use process/worker isolation for hard time and memory limits.

import eyg/interpreter/builtin
import eyg/interpreter/state

pub type Run(m) {
  Run(next: state.Next(m), steps: Int)
}

/// Start without evaluating anything. A host can keep the returned state and
/// spend its budget over several turns with `advance`.
pub fn start(expression, scope) {
  state.Loop(state.E(expression), builtin.default(scope), state.Empty)
}

/// Perform at most `limit` transitions (zero when the limit is negative).
/// `Loop` means suspended, not successful: never authorize from partial facts.
/// `Break` has the same result/error contract as the normal expression runner.
/// Subtract `steps` from the request's remaining budget across host effects,
/// reference lookups, and subsequent calls to this function.
pub fn advance(next: state.Next(m), limit: Int) -> Run(m) {
  loop(next, limit, 0)
}

fn loop(next, remaining, used) {
  case next {
    state.Break(_) -> Run(next, used)
    state.Loop(_, _, _) if remaining <= 0 -> Run(next, used)
    state.Loop(control, env, stack) ->
      loop(state.step(control, env, stack), remaining - 1, used + 1)
  }
}
