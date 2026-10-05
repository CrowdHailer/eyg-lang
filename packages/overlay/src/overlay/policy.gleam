import eyg/interpreter/state
import eyg/interpreter/value as v

/// The descision of running a policy function.
pub type Decision(meta) {
  Pass(state.Value(meta))
  Mock(state.Value(meta))
}

/// Decode the runtime decision value into Gleam value.
pub fn decision_from_value(
  value: state.Value(meta),
) -> Result(Decision(meta), Nil) {
  case value {
    v.Tagged("Pass", inner) -> Ok(Pass(inner))
    v.Tagged("Mock", inner) -> Ok(Mock(inner))
    _ -> Error(Nil)
  }
}
