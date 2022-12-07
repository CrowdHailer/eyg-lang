import gleam/option.{Option}

pub type Expression {
  Variable(label: String)
  Lambda(label: String, body: Expression)
  Apply(func: Expression, argument: Expression)
  Let(label: String, definition: Expression, body: Expression)

  // Primitive
  Integer
  Binary

  Vacant

  // Row
  // Record(fields: List(#()), Option(String))
  Select(label: String)

  Tag(label: String)
}
// match
// Effect
