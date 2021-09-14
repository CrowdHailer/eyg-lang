import eyg/typer/monotype
import eyg/ast/pattern.{Pattern}

pub type Node(m) {
  Binary(value: String)
  Tuple(elements: List(Expression(m)))
  Row(fields: List(#(String, Expression(m))))
  Variable(label: String)
  Let(pattern: Pattern, value: Expression(m), then: Expression(m))
  Function(pattern: Pattern, body: Expression(m))
  Call(function: Expression(m), with: Expression(m))
  Name(
    type_: #(String, #(List(Int), List(#(String, monotype.Monotype)))),
    then: Expression(m),
  )
  Constructor(named: String, variant: String)
  Case(
    named: String,
    value: Expression(m),
    clauses: List(#(String, String, Expression(m))),
  )
  Provider(
    config: String,
    generator: fn(String, monotype.Monotype) -> Expression(Nil),
  )
}

// m for metadata
pub type Expression(m) =
  #(m, Node(m))
