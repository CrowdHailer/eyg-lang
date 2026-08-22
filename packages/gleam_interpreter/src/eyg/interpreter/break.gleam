import eyg/interpreter/value as v
import eyg/ir/tree as ir

pub type Reason(m, c) {
  NotAFunction(v.Value(m, c))
  UndefinedVariable(String)
  UndefinedBuiltin(String)
  UndefinedReference(ir.Reference)
  Vacant
  NoMatch(term: v.Value(m, c))
  UnhandledEffect(String, v.Value(m, c))
  IncorrectTerm(expected: String, got: v.Value(m, c))
  MissingField(String)
  // The expression is unrepresentable on the runtime.
  // For example an integer outside the safe-integer range on JavaScript.
  // This halts the run with a resumable state.
  Unrepresentable(builtin: String, args: List(v.Value(m, c)))
}
