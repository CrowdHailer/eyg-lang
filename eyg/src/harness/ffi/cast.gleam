import gleam/list
import eyg/runtime/interpreter as r

pub fn any(term) {
  Ok(term)
}

// builtins might want to work with k's i.e. builtin effects
// so I have used the abort/value API rather than ok/error
pub fn integer(term) {
  case term {
    r.Integer(value) -> Ok(value)
    _ -> Error(r.IncorrectTerm("Integer", term))
  }
}

pub fn string(term) {
  case term {
    r.Str(value) -> Ok(value)
    _ -> Error(r.IncorrectTerm("String", term))
  }
}

pub fn list(term) {
  case term {
    r.LinkedList(elements) -> Ok(elements)
    _ -> Error(r.IncorrectTerm("List", term))
  }
}

pub fn field(key, inner, term) {
  case term {
    r.Record(fields) ->
      case list.key_find(fields, key) {
        Ok(value) -> inner(value)
        Error(Nil) -> Error(r.MissingField(key))
      }
    _ -> Error(r.IncorrectTerm("Record", term))
  }
}

pub fn promise(term) {
  case term {
    r.Promise(js_promise) -> Ok(js_promise)
    _ -> Error(r.IncorrectTerm("Promise", term))
  }
}

pub fn require(result, rev, env, k, then) {
  case result {
    Ok(value) -> then(value)
    Error(reason) -> r.Done(r.Abort(reason, rev, env, k))
  }
}
