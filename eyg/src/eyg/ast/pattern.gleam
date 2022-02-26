import gleam/list

pub type Pattern {
  Variable(label: String)
  Tuple(elements: List(String))
  Row(fields: List(#(String, String)))
}

pub fn variable(label) {
  Variable(label)
}

// Could be replaced with instance of
pub fn is_discard(pattern) {
  case pattern {
    Variable("") -> True
    _ -> False
  }
}

pub fn is_variable(pattern) {
  case pattern {
    Variable(_) -> True
    _ -> False
  }
}

pub fn tuple_(elements) {
  Tuple(elements)
}

pub fn is_tuple(pattern) {
  case pattern {
    Tuple(_) -> True
    _ -> False
  }
}

pub fn replace_element(pattern, index, new) {
  assert Tuple(elements) = pattern
  let pre = list.take(elements, index)
  let post = list.drop(elements, index + 1)
  let elements = list.append(pre, [new, ..post])
  Tuple(elements)
}
