import gleam/option.{None, Option}

pub type Expression {
  Variable(label: String)
  Lambda(label: String, body: Expression)
  Apply(func: Expression, argument: Expression)
  Let(label: String, definition: Expression, body: Expression)

  // Primitive
  Integer(value: Int)
  Binary(value: String)

  Vacant

  // Row
  Record(fields: List(#(String, Expression)), from: Option(String))
  Empty
  Extend(label: String)
  Select(label: String)
  Tag(label: String)
  Case(label: String)
  NoCases
  Match(
    branches: List(#(String, String, Expression)),
    tail: Option(#(String, Expression)),
  )

  // Effect
  // do/act/effect(effect is a verb and noun)
  Perform(label: String)
  // variable is the parameter name for the state
  Deep(variable: String, branches: List(#(String, String, String, Expression)))
}

pub const unit = Empty
