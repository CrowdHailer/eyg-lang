// TODO name typer
pub type Type {
  Constructor(String, List(Type))
  Variable(Int)
}

pub type PolyType {
  PolyType(forall: List(Int), type_: Type)
}
//   RowType(forall: Int, rows: List(#(String, Type)))
