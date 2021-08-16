import eyg/ast/pattern.{Pattern}

pub type Node {
  Binary(value: String)
  Tuple(elements: List(Node))
  Row(fields: List(#(String, Node)))
  Variable(label: String)
  Let(pattern: Pattern, value: Node, then: Node)
  Function(for: String, body: Node)
  Call(function: Node, with: Node)
  Constructor(named: String, variant: String)
}
