import eyg/runtime/interpreter as r

// builtins might want to work with k's i.e. builtin effects
// so I have used the abort/value API rather than ok/error
pub fn integer(term, k) {
  case term {
    r.Integer(value) -> k(value)
    _ -> r.Abort(r.IncorrectTerm("Integer", term))
  }
}

pub fn string(term, k) {
  case term {
    r.Binary(value) -> k(value)
    _ -> r.Abort(r.IncorrectTerm("Binary", term))
  }
}

pub fn list(term, k) {
  case term {
    r.LinkedList(elements) -> k(elements)
    _ -> r.Abort(r.IncorrectTerm("List", term))
  }
}
