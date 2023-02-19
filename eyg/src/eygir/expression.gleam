import gleam/list
import gleam/option.{None, Some}

pub type Expression {
  Variable(label: String)
  Lambda(label: String, body: Expression)
  Apply(func: Expression, argument: Expression)
  Let(label: String, definition: Expression, body: Expression)

  // Primitive
  Integer(value: Int)
  Binary(value: String)

  Tail
  // type system won't allow improper list
  // Is there a need for first class list, not as both are addressible as expressions
  // There is an idea that I can have restrictive record etc but stil keep
  // super simple fn application
  Cons

  Vacant

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
  // Macro maybe
  Provider(Expression)
}

pub const unit = Empty

pub const true = Apply(Tag("True"), unit)

pub const false = Apply(Tag("False"), unit)

pub fn ok(value) {
  Apply(Tag("Ok"), value)
}

pub fn error(value) {
  Apply(Tag("Error"), value)
}

// We calling case or match? what's my preferred name not just avoiding gleam collision
pub fn match(branches, tail) {
  let final = case tail {
    Some(#(param, body)) -> Lambda(param, body)
    None -> NoCases
  }
  list.fold_right(
    branches,
    final,
    fn(acc, branch) {
      let #(label, param, then) = branch
      Apply(Apply(Case(label), Lambda(param, then)), acc)
    },
  )
}
