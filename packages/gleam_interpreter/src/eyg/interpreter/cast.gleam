import eyg/interpreter/break
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result.{try}

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
    v.String(value) -> Ok(value)
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

pub fn as_list_of(value, decoder) {
  case value {
    v.LinkedList(elements) -> list.try_map(elements, decoder)
    _ -> Error(break.IncorrectTerm("List", value))
  }
}

pub fn as_record(value) {
  case value {
    v.Record(fields) -> Ok(fields)
    _ -> Error(break.IncorrectTerm("Record", value))
  }
}

pub fn as_unit(value, is) {
  use fields <- try(as_record(value))
  case dict.size(fields) {
    0 -> Ok(is)
    _ -> Error(break.MissingField("actually to many fields"))
  }
}

pub fn field(key, inner, value) {
  use fields <- try(as_record(value))
  case dict.get(fields, key) {
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

pub fn as_varient(value, decoders) {
  use #(tag, inner) <- try(as_tagged(value))
  case list.key_find(decoders, tag) {
    Ok(decoder) -> decoder(inner)
    Error(Nil) ->
      Error(break.IncorrectTerm("Variant bbetter error needed", value))
  }
}

pub fn as_option(value, decoder) {
  as_varient(value, [
    #("Some", fn(inner) {
      use inner <- try(decoder(inner))
      Ok(Some(inner))
    }),
    #("None", as_unit(_, None)),
  ])
}

pub fn as_promise(term) {
  case term {
    v.Promise(js_promise) -> Ok(js_promise)
    _ -> Error(break.IncorrectTerm("Promise", term))
  }
}
