import gleam/string
import eyg/runtime/value.{type Value}

pub type Reason(m, c) {
  NotAFunction(Value(m, c))
  UndefinedVariable(String)
  Vacant(comment: String)
  NoMatch(term: Value(m, c))
  UnhandledEffect(String, Value(m, c))
  IncorrectTerm(expected: String, got: Value(m, c))
  MissingField(String)
}

pub fn reason_to_string(reason) {
  case reason {
    UndefinedVariable(var) -> string.append("variable undefined: ", var)
    IncorrectTerm(expected, got) ->
      string.concat([
        "unexpected term, expected: ",
        expected,
        " got: ",
        value.debug(got),
      ])
    MissingField(field) -> string.concat(["missing record field: ", field])
    NoMatch(term) ->
      string.concat(["no cases matched for: ", value.debug(term)])
    NotAFunction(term) ->
      string.concat(["function expected got: ", value.debug(term)])
    UnhandledEffect("Abort", reason) ->
      string.concat(["Aborted with reason: ", value.debug(reason)])
    UnhandledEffect(effect, lift) ->
      string.concat(["unhandled effect ", effect, "(", value.debug(lift), ")"])
    Vacant(note) -> string.concat(["tried to run a todo: ", note])
  }
}
