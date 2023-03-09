import eyg/runtime/interpreter as r

// builtins might want to work with k's i.e. builtin effects
// so I have used the abort/value API rather than ok/error
pub fn string(term, k) {
  case term {
    r.Binary(value) -> k(value)
    _ -> r.Abort(r.IncorrectTerm("List", term))
  }
}

pub fn list(term, k) {
  case term {
    r.LinkedList(elements) -> k(elements)
    _ -> r.Abort(r.IncorrectTerm("List", term))
  }
}
