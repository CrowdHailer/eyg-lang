import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{infer}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn infer_variant_test() {
  let scope = []
  let untyped = ast.Call(ast.Constructor("Boolean", "True"), ast.Tuple([]))
  let Ok(type_) = infer(untyped, scope)
  assert monotype.Nominal("Boolean", []) = type_
}

pub fn infer_concrete_parameterised_variant_test() {
  let scope = []
  //   Think we might always put in tuple in my language
  let untyped = ast.Call(ast.Constructor("Option", "Some"), ast.Binary("value"))
  let Ok(type_) = infer(untyped, scope)
  assert monotype.Nominal("Option", [monotype.Binary]) = type_
}

pub fn infer_unspecified_parameterised_variant_test() {
  let scope = []
  let untyped = ast.Call(ast.Constructor("Option", "None"), ast.Tuple([]))
  let Ok(type_) = infer(untyped, scope)
  assert monotype.Nominal("Option", [monotype.Unbound(_)]) = type_
}

pub fn unknown_named_type_test() {
  let scope = []
  let untyped = ast.Call(ast.Constructor("Foo", "X"), ast.Tuple([]))
  let Error(reason) = infer(untyped, scope)
  assert typer.UnknownType("Foo") = reason
}

pub fn unknown_variant_test() {
  let scope = []
  let untyped = ast.Call(ast.Constructor("Boolean", "Perhaps"), ast.Tuple([]))
  let Error(reason) = infer(untyped, scope)
  assert typer.UnknownVariant("Perhaps", "Boolean") = reason
}
// TODO creating duplicate name
// TODO pattern destructure OR case
// sum types don't need to be nominal, Homever there are very helpful to label the alternatives and some degree of nominal typing is useful for global look up
// pub fn true(x) {
//   fn(a, b) {a(x)}
// }
// pub fn false(x) {
//   fn(a, b) {b(x)}
// }
// fn main() { 
//   let bool = case 1 {
//     1 -> true([])
//     2 -> false([])
//   }
//   let r = bool(fn (_) {"hello"}, fn (_) {"world"})
// }
