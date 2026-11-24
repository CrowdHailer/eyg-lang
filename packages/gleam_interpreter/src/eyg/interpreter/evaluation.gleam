//// Compose evaluation deferring effect handling and reference resolution to the caller.

import eyg/interpreter/state

/// The interpreter's successful result or failure.
/// Expressions return a value blocks return an optional value and scope.
pub type Outcome(value, m) =
  Result(value, state.Debug(m))

/// A completed computation or an interpreter evaluation for the host to finish.
///
/// The host drives the interpreter to completion or a terminal failure before
/// calling `resume`. Resolving one reference or effect may encounter another;
/// continue with the matching interpreter's resume function until it is finished.
/// A pure driver resolves references but returns unhandled effects as failures.
pub type Evaluation(a, value, m) {
  Done(a)
  Conclude(
    returned: Outcome(value, m),
    resume: fn(Outcome(value, m)) -> Evaluation(a, value, m),
  )
}

/// Ask the host to finish an expression or block evaluation.
pub fn await(
  returned: Outcome(value, m),
) -> Evaluation(Outcome(value, m), value, m) {
  Conclude(returned, Done)
}

pub fn then(
  evaluation: Evaluation(a, value, m),
  next: fn(a) -> Evaluation(b, value, m),
) -> Evaluation(b, value, m) {
  case evaluation {
    Done(value) -> next(value)
    Conclude(returned, resume) ->
      Conclude(returned, fn(outcome) { then(resume(outcome), next) })
  }
}

pub fn map(
  evaluation: Evaluation(a, value, m),
  transform: fn(a) -> b,
) -> Evaluation(b, value, m) {
  then(evaluation, fn(value) { Done(transform(value)) })
}
