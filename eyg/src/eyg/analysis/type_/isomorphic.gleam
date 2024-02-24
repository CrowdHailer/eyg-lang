// isomorphic as the opposite of kinded, all types have the same kind.
// This is my terminology.
// Avoid calling simple, is there a more precise name

pub type Type(var) {
  Var(key: var)
  Fun(Type(var), Type(var), Type(var))
  Binary
  Integer
  String
  List(Type(var))
  Record(Type(var))
  Union(Type(var))
  Empty
  RowExtend(String, Type(var), Type(var))
  EffectExtend(String, #(Type(var), Type(var)), Type(var))
}
