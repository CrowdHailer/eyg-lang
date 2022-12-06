pub type Row(kind) {
  RowClosed
  RowOpen(Int)
  // Needs to be type for Type variable -> PR to kind in f-sharp code
  RowExtend(label: String, value: kind, tail: Row(kind))
}

pub type Type {
  Var(Int)
  Integer
  Binary
  Fun(Type, Row(#(Type, Type)), Type)
  // Row parameterised by T for effects
  Union(Row(Type))
  Record(Row(Type))
}
