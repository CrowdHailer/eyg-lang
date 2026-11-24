//// Compose evaluation deferring effect handling and reference resolution to the caller.

import eyg/interpreter/state

pub type Outcome(m) =
  Result(state.Value(m), state.Debug(m))

/// A completed computation or an interpreter evaluation for the host to finish.
///
/// The `resume` function is normally called with the result of `expression.resume` or `block.resume`, after resolving a reference or implementing and effect.
/// Some cases will return a different error for example if executing a policy for an effect fails.
pub type Evaluation(a, m) {
  Done(a)
  Conclude(returned: Outcome(m), resume: fn(Outcome(m)) -> Evaluation(a, m))
}

/// Push resol
pub fn await(returned: Outcome(m)) -> Evaluation(Outcome(m), m) {
  Conclude(returned, Done)
}

pub fn then(
  evaluation: Evaluation(a, m),
  next: fn(a) -> Evaluation(b, m),
) -> Evaluation(b, m) {
  case evaluation {
    Done(value) -> next(value)
    Conclude(returned, resume) ->
      Conclude(returned, fn(outcome) { then(resume(outcome), next) })
  }
}

pub fn map(
  evaluation: Evaluation(a, m),
  transform: fn(a) -> b,
) -> Evaluation(b, m) {
  then(evaluation, fn(value) { Done(transform(value)) })
}
