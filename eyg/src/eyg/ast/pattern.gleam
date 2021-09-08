pub type Pattern {
  Variable(label: String)
  Tuple(elements: List(String))
  Row(fields: List(#(String, String)))
}

pub fn tuple_(elements) {
  Tuple(elements)
}

pub fn variable(label) {
  Variable(label)
}
