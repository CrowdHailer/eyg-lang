import gleam/option.{None, Option}

// hd Ok({value, rest}) Error({})
// head(list)(value-> rest -> {})(_ -> {})
// fix as a variable that exists. Shallow handlers

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
  Record(fields: List(#(String, Expression)), from: Option(String))
  Empty
  Extend(label: String)
  Select(label: String)
  Overwrite(label: String)
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
  Handle(label: String)
}

pub const unit = Empty
