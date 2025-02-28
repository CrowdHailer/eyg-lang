import eyg/interpreter/value as v

pub type Reason(m, c) {
  NotAFunction(v.Value(m, c))
  UndefinedVariable(String)
  UndefinedBuiltin(String)
  UndefinedReference(String)
  UndefinedRelease(package: String, release: Int, cid: String)
  Vacant
  NoMatch(term: v.Value(m, c))
  UnhandledEffect(String, v.Value(m, c))
  IncorrectTerm(expected: String, got: v.Value(m, c))
  MissingField(String)
}
