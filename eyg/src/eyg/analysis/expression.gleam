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
  Record(fields: List(#(String, Expression)), from: Option(String))
  Select(label: String)
  Tag(label: String)
  Match(
    value: Expression,
    branches: List(#(String, String, Expression)),
    tail: Option(#(String, Expression)),
  )

  // Effect
  // do/act/effect(effect is a verb and noun)
  Perform(label: String)
}
// TODO read koka paper
// single label only but we need continuation etc
// Handle(label: String, param String, )  fn(a) -> <label x,y | eff>
// Handle with no label fn(fn(a, lslslsll, b), action) -> exec
