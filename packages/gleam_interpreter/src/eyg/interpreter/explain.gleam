//// Budgeted evaluation returning ordinary values and engine-generated proof
//// trees for every completed resolve. No partial evidence authorizes a request.

import eyg/interpreter/builtin
import eyg/interpreter/proof
import eyg/interpreter/state
import gleam/list

pub type Explained(m) {
  Explained(
    value: state.Value(m),
    queries: List(proof.Query(m, state.Context(m))),
  )
}

pub type Run(m) {
  Completed(result: Result(Explained(m), state.Debug(m)), steps: Int)
  Suspended(next: state.Next(m), steps: Int)
}

pub fn start(expression, scope) {
  state.Loop(
    state.E(expression),
    builtin.default(scope),
    state.Stack(state.Explain([]), expression.1, state.Empty),
  )
}

/// The budget is in interpreter transitions. Subtract `steps` when resuming.
pub fn advance(next: state.Next(m), limit: Int) -> Run(m) {
  loop(next, limit, 0)
}

fn loop(next, remaining, used) {
  case next {
    state.Break(Error(error)) -> Completed(Error(error), used)
    state.Break(Ok(value)) -> Completed(Ok(Explained(value, [])), used)
    state.Loop(_, _, _) if remaining <= 0 -> Suspended(next, used)
    state.Loop(
      state.V(value),
      _,
      state.Stack(state.Explain(queries), _, state.Empty),
    ) -> Completed(Ok(Explained(value, list.reverse(queries))), used + 1)
    state.Loop(control, env, stack) ->
      loop(state.step(control, env, stack), remaining - 1, used + 1)
  }
}
