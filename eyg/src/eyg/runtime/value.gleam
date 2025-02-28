import eyg/interpreter/value as v
import gleam/dict
import gleam/int
import gleam/list
import gleam/string

pub fn print_bit_string(value) {
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
pub fn debug(term) {
  case term {
    v.Binary(value) -> print_bit_string(value)
    v.Integer(value) -> int.to_string(value)
    v.String(value) -> string.concat(["\"", value, "\""])
    v.LinkedList(items) ->
      list.map(items, debug)
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
    v.Tagged(label, value) -> string.concat([label, "(", debug(value), ")"])
    v.Closure(param, _, _) -> string.concat(["(", param, ") -> { ... }"])
    v.Partial(d, args) ->
      string.concat([
        "Partial: ",
        string.inspect(d),
        " ",
        ..list.intersperse(list.map(args, debug), ", ")
      ])
    v.Promise(_) -> string.concat(["Promise: "])
  }
}

fn field_to_string(field) {
  let #(k, v) = field
  string.concat([k, ": ", debug(v)])
}
