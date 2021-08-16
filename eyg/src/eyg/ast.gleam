import eyg/ast/pattern.{Pattern}

pub type Node {
  Binary(value: String)
  Tuple(elements: List(Node))
  Row(fields: List(#(String, Node)))
  Variable(label: String)
  Let(pattern: Pattern, value: Node, then: Node)
  Function(for: String, body: Node)
}
