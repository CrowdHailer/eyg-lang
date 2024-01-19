import gleam/list
import gleam/result
import eyg/runtime/value as v
import eyg/runtime/break

pub fn any(term) {
  Ok(term)
}

pub fn as_integer(value) {
  case value {
    v.Integer(value) -> Ok(value)
    _ -> Error(break.IncorrectTerm("Integer", value))
  }
}

pub fn as_string(value) {
  case value {
    v.Str(value) -> Ok(value)
    _ -> Error(break.IncorrectTerm("String", value))
  }
}

pub fn as_binary(value) {
  case value {
    v.Binary(value) -> Ok(value)
    _ -> Error(break.IncorrectTerm("Binary", value))
  }
}

pub fn as_list(value) {
  case value {
    v.LinkedList(elements) -> Ok(elements)
    _ -> Error(break.IncorrectTerm("List", value))
  }
}

pub fn as_record(value) {
  case value {
    v.Record(fields) -> Ok(fields)
    _ -> Error(break.IncorrectTerm("Record", value))
  }
}

pub fn field(key, inner, value) {
  use fields <- result.then(as_record(value))
  case list.key_find(fields, key) {
    Ok(value) -> inner(value)
    Error(Nil) -> Error(break.MissingField(key))
  }
}

pub fn as_tagged(value) {
  case value {
    v.Tagged(label, inner) -> Ok(#(label, inner))
    _ -> Error(break.IncorrectTerm("Tagged", value))
  }
}

pub fn as_promise(term) {
  case term {
    v.Promise(js_promise) -> Ok(js_promise)
    _ -> Error(break.IncorrectTerm("Promise", term))
  }
}
