pub type Node {
  Binary(value: String)
  Tuple(elements: List(Node))
  Row(fields: List(#(String, Node)))
  Variable(label: String)
}
