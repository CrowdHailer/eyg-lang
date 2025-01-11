import gleam/int
import gleam/list
import gleam/string

// this prints in the eyg format,
// doesn't belong in this file but was the first sensible place to store the function
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

pub type Expression {
  Variable(label: String)
  Lambda(label: String, body: Expression)
  Apply(func: Expression, argument: Expression)
  Let(label: String, definition: Expression, body: Expression)

  // Primitive
  // TODO encode/decode
  Binary(value: BitArray)
  Integer(value: Int)
  Str(value: String)

  Tail
  // type system won't allow improper list
  // Is there a need for first class list, not as both are addressible as expressions
  // There is an idea that I can have restrictive record etc but stil keep
  // super simple fn application
  Cons

  Vacant(comment: String)

  // Row
  Empty
  Extend(label: String)
  Select(label: String)
  Overwrite(label: String)
  Tag(label: String)
  Case(label: String)
  NoCases

  // Effect
  // do/act/effect(effect is a verb and noun)
  Perform(label: String)
  Handle(label: String)
  // Experiment in stateful Effects
  Shallow(label: String)

  Builtin(identifier: String)
  Reference(identifier: String)
  NamedReference(package: String, release: Int)
}

pub const unit = Empty

pub const true = Apply(Tag("True"), unit)

pub const false = Apply(Tag("False"), unit)

pub fn list(items) {
  do_list(list.reverse(items), Tail)
}

pub fn do_list(reversed, acc) {
  case reversed {
    [item, ..rest] -> do_list(rest, Apply(Apply(Cons, item), acc))
    [] -> acc
  }
}

pub fn record(items) {
  do_record(list.reverse(items), Empty)
}

pub fn do_record(reversed, acc) {
  case reversed {
    [#(label, value), ..rest] ->
      do_record(rest, Apply(Apply(Extend(label), value), acc))
    [] -> acc
  }
}

pub fn do_overwrite(reversed, acc) {
  case reversed {
    [#(label, value), ..rest] ->
      do_overwrite(rest, Apply(Apply(Overwrite(label), value), acc))
    [] -> acc
  }
}

pub fn tagged(tag, value) {
  Apply(Tag(tag), value)
}

fn do_exp_to_block(exp, acc) {
  case exp {
    Let(label, value, then) -> do_exp_to_block(then, [#(label, value), ..acc])
    _ -> #(list.reverse(acc), exp)
  }
}

pub fn expression_to_block(exp) {
  do_exp_to_block(exp, [])
}

fn do_block_to_exp(reversed, then) {
  case reversed {
    [] -> then
    [#(label, value), ..rest] -> do_block_to_exp(rest, Let(label, value, then))
  }
}

pub fn block_to_expression(assigns, then) {
  do_block_to_exp(list.reverse(assigns), then)
}
