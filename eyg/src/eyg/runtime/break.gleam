import eyg/interpreter/break
import eyg/runtime/value as old_value
import gleam/int
import gleam/string

pub fn reason_to_string(reason) {
  case reason {
    break.UndefinedVariable(var) -> "variable undefined: " <> var
    break.UndefinedBuiltin(var) -> "variable builtin: " <> var
    break.UndefinedReference(id) -> "reference undefined: #" <> id
    break.UndefinedRelease(package, release, _cid) ->
      "release undefined: @" <> package <> ":" <> int.to_string(release)
    break.IncorrectTerm(expected, got) ->
      string.concat([
        "unexpected term, expected: ",
        expected,
        " got: ",
        old_value.debug(got),
      ])
    break.MissingField(field) -> "missing record field: " <> field
    break.NoMatch(term) -> "no cases matched for: " <> old_value.debug(term)
    break.NotAFunction(term) ->
      "function expected got: " <> old_value.debug(term)
    break.UnhandledEffect("Abort", reason) ->
      "Aborted with reason: " <> old_value.debug(reason)
    break.UnhandledEffect(effect, lift) ->
      "unhandled effect " <> effect <> "(" <> old_value.debug(lift) <> ")"
    break.Vacant -> "tried to run a todo"
  }
}
