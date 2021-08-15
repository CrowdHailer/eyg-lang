pub type Pattern {
  Variable(label: String)
  Tuple(elements: List(String))
  Row(fields: List(#(String, String)))
}
