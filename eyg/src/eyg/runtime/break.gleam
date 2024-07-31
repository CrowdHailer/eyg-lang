import eyg/runtime/value.{type Value}
import gleam/string

pub type Reason(m, c) {
  NotAFunction(Value(m, c))
  UndefinedReference(String)
  UndefinedVariable(String)
  Vacant(comment: String)
  NoMatch(term: Value(m, c))
  UnhandledEffect(String, Value(m, c))
  IncorrectTerm(expected: String, got: Value(m, c))
  MissingField(String)
}

pub fn reason_to_string(reason) {
  case reason {
    UndefinedVariable(var) -> "variable undefined: " <> var
    UndefinedReference(id) -> "reference undefined: #" <> id
    IncorrectTerm(expected, got) ->
      string.concat([
        "unexpected term, expected: ",
        expected,
        " got: ",
        value.debug(got),
      ])
    MissingField(field) -> "missing record field: " <> field
    NoMatch(term) -> "no cases matched for: " <> value.debug(term)
    NotAFunction(term) -> "function expected got: " <> value.debug(term)
    UnhandledEffect("Abort", reason) ->
      "Aborted with reason: " <> value.debug(reason)
    UnhandledEffect(effect, lift) ->
      "unhandled effect " <> effect <> "(" <> value.debug(lift) <> ")"
    Vacant(note) -> "tried to run a todo: " <> note
  }
}
