import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/javascript/promise.{type Promise as JSPromise}
import gleam/option.{None, Some}

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
  Partial(Switch(context), List(Value(m, context)))
  Promise(JSPromise(Value(m, context)))
}

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
  Resume(context)
  Builtin(String)
}

pub fn unit() {
  Record(dict.new())
}

pub fn true() {
  Tagged("True", unit())
}

pub fn false() {
  Tagged("False", unit())
}

pub fn bool(in) {
  case in {
    True -> true()
    False -> false()
  }
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
