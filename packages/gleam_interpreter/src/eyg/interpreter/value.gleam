import eyg/ir/tree as ir
import gleam/dict.{type Dict}
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
  Partial(switch: Switch(context), arguments: List(Value(m, context)))
}

pub type Switch(context) {
  Cons
  Extend(label: String)
  Overwrite(label: String)
  Select(label: String)
  Tag(label: String)
  Match(label: String)
  NoCases
  Perform(label: String)
  Handle(label: String)
  Shallow(label: String)
  Mask(label: String)
  Pure
  Resume(context)
  Builtin(identifier: String)
}

pub fn unit() {
  Record(dict.new())
}

pub fn tag(label) {
  Partial(Tag(label), [])
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
