import eyg/interpreter/value as v

pub type Reason(m, c) {
  NotAFunction(v.Value(m, c))
  UndefinedReference(String)
  UndefinedVariable(String)
  UndefinedBuiltin(String)
  Vacant
  NoMatch(term: v.Value(m, c))
  UnhandledEffect(String, v.Value(m, c))
  IncorrectTerm(expected: String, got: v.Value(m, c))
  MissingField(String)
}
