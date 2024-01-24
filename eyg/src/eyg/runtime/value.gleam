import gleam/int
import gleam/list
import gleam/string
import gleam/javascript/promise.{type Promise as JSPromise}
import eygir/expression as e

pub type Value(context) {
  Binary(value: BitArray)
  Integer(value: Int)
  Str(value: String)
  LinkedList(elements: List(Value(context)))
  Record(fields: List(#(String, Value(context))))
  Tagged(label: String, value: Value(context))
  Closure(
    param: String,
    body: e.Expression,
    env: List(#(String, Value(context))),
    path: List(Int),
  )
  Partial(Switch(context), List(Value(context)))
  Promise(JSPromise(Value(context)))
}

// context is a captured part of interpretation, it's type depends on implementation
pub type Switch(context) {
  Cons
  Extend(String)
  Overwrite(String)
  Select(String)
  Tag(String)
  Match(String)
  NoCases
  Perform(String)
  Handle(String)
  // env needs terms/value and values need terms/env
  // reversed has no reference to extrinsic, might be different context
  Resume(context)
  Shallow(String)
  Builtin(String)
}

// This might not give in runtime core, more runtime presentation
pub fn debug(term) {
  case term {
    Binary(value) -> e.print_bit_string(value)
    Integer(value) -> int.to_string(value)
    Str(value) -> string.concat(["\"", value, "\""])
    LinkedList(items) ->
      list.map(items, debug)
      |> list.intersperse(", ")
      |> list.prepend("[")
      |> list.append(["]"])
      |> string.concat
    Record(fields) ->
      fields
      |> list.map(field_to_string)
      |> list.intersperse(", ")
      |> list.prepend("{")
      |> list.append(["}"])
      |> string.concat
    Tagged(label, value) -> string.concat([label, "(", debug(value), ")"])
    Closure(param, _, _, _) -> string.concat(["(", param, ") -> { ... }"])
    Partial(d, args) ->
      string.concat([
        "Partial: ",
        string.inspect(d),
        " ",
        ..list.intersperse(list.map(args, debug), ", ")
      ])
    Promise(_) -> string.concat(["Promise: "])
  }
}

fn field_to_string(field) {
  let #(k, v) = field
  string.concat([k, ": ", debug(v)])
}

pub const unit = Record([])

pub const true = Tagged("True", unit)

pub const false = Tagged("False", unit)

pub fn ok(value) {
  Tagged("Ok", value)
}

pub fn error(reason) {
  Tagged("Error", reason)
}