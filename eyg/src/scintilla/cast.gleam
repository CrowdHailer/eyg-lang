import scintilla/value as v
import scintilla/reason as r

pub fn as_integer(value) {
  case value {
    v.I(value) -> Ok(value)
    _ -> Error(r.IncorrectTerm("Integer", value))
  }
}

pub fn as_float(value) {
  case value {
    v.F(value) -> Ok(value)
    _ -> Error(r.IncorrectTerm("Float", value))
  }
}

pub fn as_boolean(value) {
  case value {
    v.R("True", []) -> Ok(True)
    v.R("False", []) -> Ok(False)
    _ -> Error(r.IncorrectTerm("Boolean", value))
  }
}

pub fn as_string(value) {
  case value {
    v.S(value) -> Ok(value)
    _ -> Error(r.IncorrectTerm("String", value))
  }
}

pub fn as_tuple(value) {
  case value {
    v.T(elements) -> Ok(elements)
    _ -> Error(r.IncorrectTerm("Tuple", value))
  }
}

pub fn as_list(value) {
  case value {
    v.L(elements) -> Ok(elements)
    _ -> Error(r.IncorrectTerm("List", value))
  }
}
