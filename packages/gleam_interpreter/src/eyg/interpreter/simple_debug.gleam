//// A naive representation of EYG values as a string.
//// Note the returned string can be any size and applications are best of writing their own visualisation.

import eyg/interpreter/break
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import multiformats/cid/v1

/// Describe a reason to stop execution
pub fn describe(reason) {
  case reason {
    break.UndefinedVariable(var) -> "variable undefined: " <> var
    break.UndefinedBuiltin(var) -> "builtin undefined: !" <> var
    break.UndefinedReference(id) -> "reference undefined: #" <> v1.to_string(id)
    break.UndefinedRelease(package, release, _cid) ->
      "release undefined: @" <> package <> ":" <> int.to_string(release)
    break.IncorrectTerm(expected, got) ->
      string.concat([
        "unexpected term, expected: ",
        expected,
        " got: ",
        inspect(got),
      ])
    break.MissingField(field) -> "missing record field: " <> field
    break.NoMatch(term) -> "no cases matched for: " <> inspect(term)
    break.NotAFunction(term) -> "function expected got: " <> inspect(term)
    break.UnhandledEffect("Abort", reason) ->
      "Aborted with reason: " <> inspect(reason)
    break.UnhandledEffect(effect, lift) ->
      "unhandled effect " <> effect <> "(" <> inspect(lift) <> ")"
    break.Vacant -> "tried to run a todo"
  }
}

/// Inspect a value.
pub fn inspect(value: v.Value(_, _)) -> String {
  do_inspect(value, 0)
}

fn do_inspect(value: v.Value(_, _), indent: Int) -> String {
  let indent_str = string.repeat("  ", indent)
  case value {
    v.String(s) -> "\"" <> escape_string(s) <> "\""
    v.Integer(i) -> int.to_string(i)
    v.Binary(b) -> {
      let size = bit_array.byte_size(b)
      let encoded = bit_array.base64_encode(b, True)
      "Binary(" <> int.to_string(size) <> " bytes): " <> encoded
    }
    v.Tagged(label, inner) -> {
      label <> "(" <> do_inspect(inner, indent) <> ")"
    }
    v.Record(fields) -> {
      let items =
        dict.to_list(fields)
        |> list.map(fn(pair) {
          let #(key, val) = pair
          indent_str <> "  " <> key <> ": " <> do_inspect(val, indent + 1)
        })
        |> string.join("\n")
      "{\n" <> items <> "\n" <> indent_str <> "}"
    }
    v.LinkedList(items) -> {
      case items {
        [] -> "[]"
        _ -> {
          let rendered =
            items
            |> list.map(fn(item) {
              indent_str <> "  " <> do_inspect(item, indent + 1)
            })
            |> string.join(",\n")
          "[\n" <> rendered <> "\n" <> indent_str <> "]"
        }
      }
    }
    v.Closure(param, _, _) -> "fn(" <> param <> ") -> {...}"
    v.Partial(func, args) -> {
      let args_str =
        args
        |> list.map(fn(a) { do_inspect(a, indent) })
        |> string.join(", ")
      "Partial(" <> string.inspect(func) <> ", " <> args_str <> ")"
    }
    v.Promise(_) -> "Promise(...)"
  }
}

fn escape_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}
