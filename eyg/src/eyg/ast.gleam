import eyg/ast/pattern.{Pattern}
import eyg/typer/monotype

pub type Node {
  Binary(value: String)
  Tuple(elements: List(Node))
  Row(fields: List(#(String, Node)))
  Variable(label: String)
  Let(pattern: Pattern, value: Node, then: Node)
  Function(for: String, body: Node)
  Call(function: Node, with: Node)
  Name(
    type_: #(String, #(List(Int), List(#(String, monotype.Monotype)))),
    then: Node,
  )
  Constructor(named: String, variant: String)
  Case(named: String, value: Node, clauses: List(#(String, String, Node)))
  Provider(id: Int, generator: fn(monotype.Monotype) -> Node)
}
