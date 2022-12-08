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
// TODO read koka paper
// single label only but we need continuation etc
// Handle with no label fn(fn(a, lslslsll, b), action) -> exec
Handle(label: String, param String, )  fn(a) -> <label x,y | eff>
}

handle {
  Log x, cont -> 
}

// need other syntaxes
// Needs a raise function that takes a union
handle(match {
  Log msg, k -> #(msg, k([]))
  Return value -> #("", value)
  other -> do(other)
})

// can I transpile all the row building into placeholders and application
// see heyleighs comment
Handle()
handle(Log)(Effect(msg, k) | Return value)(comp)(arg)
handle(Log)(fn(msg, k){}, fn(ret) {})(bob)
Case(Foo)(fn(x), fn(res))