import eyg/interpreter/value as v
import multiformats/cid/v1

pub type Reason(m, c) {
  NotAFunction(v.Value(m, c))
  UndefinedVariable(String)
  UndefinedBuiltin(String)
  UndefinedReference(v1.Cid)
  UndefinedRelease(package: String, release: Int, module: v1.Cid)
  Vacant
  NoMatch(term: v.Value(m, c))
  UnhandledEffect(String, v.Value(m, c))
  IncorrectTerm(expected: String, got: v.Value(m, c))
  MissingField(String)
}
