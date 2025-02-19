import eyg/interpreter/break
import eyg/interpreter/value as v
import gleam/dict
import gleam/int
import gleam/list
import gleam/string

pub fn reason_to_string(reason) {
  case reason {
    break.UndefinedVariable(var) -> "variable undefined: " <> var
    break.UndefinedBuiltin(var) -> "builtin undefined: !" <> var
    break.UndefinedReference(id) -> "reference undefined: #" <> id
    break.UndefinedRelease(package, release, _cid) ->
      "release undefined: @" <> package <> ":" <> int.to_string(release)
    break.IncorrectTerm(expected, got) ->
      string.concat([
        "unexpected term, expected: ",
        expected,
        " got: ",
        value_to_string(got),
      ])
    break.MissingField(field) -> "missing record field: " <> field
    break.NoMatch(term) -> "no cases matched for: " <> value_to_string(term)
    break.NotAFunction(term) ->
      "function expected got: " <> value_to_string(term)
    break.UnhandledEffect("Abort", reason) ->
      "Aborted with reason: " <> value_to_string(reason)
    break.UnhandledEffect(effect, lift) ->
      "unhandled effect " <> effect <> "(" <> value_to_string(lift) <> ")"
    break.Vacant -> "tried to run a todo"
  }
}

fn print_bit_string(value) {
  bit_string_to_integers(value, [])
  |> list.map(int.to_string)
  |> string.join(" ")
  |> string.append(">")
  |> string.append("<", _)
}

fn bit_string_to_integers(value, acc) {
  case value {
    <<byte, rest:bytes>> -> bit_string_to_integers(rest, [byte, ..acc])
    _ -> list.reverse(acc)
  }
}

// This might not give in runtime core, more runtime presentation
pub fn value_to_string(term) {
  case term {
    v.Binary(value) -> print_bit_string(value)
    v.Integer(value) -> int.to_string(value)
    v.String(value) -> string.concat(["\"", value, "\""])
    v.LinkedList(items) ->
      list.map(items, value_to_string)
      |> list.intersperse(", ")
      |> list.prepend("[")
      |> list.append(["]"])
      |> string.concat
    v.Record(fields) ->
      fields
      |> dict.to_list
      |> list.map(field_to_string)
      |> list.intersperse(", ")
      |> list.prepend("{")
      |> list.append(["}"])
      |> string.concat
    v.Tagged(label, value) ->
      string.concat([label, "(", value_to_string(value), ")"])
    v.Closure(param, _, _) -> string.concat(["(", param, ") -> { ... }"])
    v.Partial(d, args) ->
      string.concat([
        "Partial: ",
        string.inspect(d),
        " ",
        ..list.intersperse(list.map(args, value_to_string), ", ")
      ])
    v.Promise(_) -> string.concat(["Promise: "])
  }
}

fn field_to_string(field) {
  let #(k, v) = field
  string.concat([k, ": ", value_to_string(v)])
}
