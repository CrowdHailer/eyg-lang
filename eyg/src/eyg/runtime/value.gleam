import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/int
import gleam/javascript/promise.{type Promise as JSPromise}
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub type Value(m, context) {
  Binary(value: BitArray)
  Integer(value: Int)
  String(value: String)
  LinkedList(elements: List(Value(m, context)))
  Record(fields: Dict(String, Value(m, context)))
  Tagged(label: String, value: Value(m, context))
  Closure(
    param: String,
    body: ir.Node(m),
    env: List(#(String, Value(m, context))),
  )
  // meta is in closure to extract types in env from type env
  // this is rather than typechecking all the values in the env which themselves have an env
  // wouldn't be needed if all the env checking had sensible has memoisation
  Partial(Switch(context), List(Value(m, context)))
  Promise(JSPromise(Value(m, context)))
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
  Builtin(String)
}

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
    Binary(value) -> print_bit_string(value)
    Integer(value) -> int.to_string(value)
    String(value) -> string.concat(["\"", value, "\""])
    LinkedList(items) ->
      list.map(items, debug)
      |> list.intersperse(", ")
      |> list.prepend("[")
      |> list.append(["]"])
      |> string.concat
    Record(fields) ->
      fields
      |> dict.to_list
      |> list.map(field_to_string)
      |> list.intersperse(", ")
      |> list.prepend("{")
      |> list.append(["}"])
      |> string.concat
    Tagged(label, value) -> string.concat([label, "(", debug(value), ")"])
    Closure(param, _, _) -> string.concat(["(", param, ") -> { ... }"])
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

// pub const unit = Record(dict.new())
pub fn unit() {
  Record(dict.new())
}

pub fn true() {
  Tagged("True", unit())
}

pub fn false() {
  Tagged("False", unit())
}

pub fn ok(value) {
  Tagged("Ok", value)
}

pub fn error(reason) {
  Tagged("Error", reason)
}

pub fn some(value) {
  Tagged("Some", value)
}

pub fn none() {
  Tagged("None", unit())
}

pub fn option(option, cast) {
  case option {
    Some(value) -> some(cast(value))
    None -> none()
  }
}
