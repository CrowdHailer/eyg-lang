import eyg/analysis/jm/type_ as t

pub type Reason {
  MissingVariable(String)
  // unification
  TypeMismatch(t.Type, t.Type)
  RowMismatch(String)
  InvalidTail(t.Type)
  RecursiveType
}
