import gleam/option.{None}
import eyg/ast
import eyg/typer.{infer}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn infer_type_of_tuple_test() {
  let scope = []
  let untyped = ast.Tuple([])
  let Ok(type_) = infer(untyped, scope)
  assert monotype.Tuple([]) = type_
}

pub fn infer_type_of_nested_tuple_test() {
  let scope = []
  let untyped = ast.Tuple([ast.Tuple([])])
  let Ok(type_) = infer(untyped, scope)
  assert monotype.Tuple([monotype.Tuple([])]) = type_
}

pub fn infer_binary_test() {
  let scope = []
  let untyped = ast.Binary("Hello")
  let Ok(type_) = infer(untyped, scope)
  assert monotype.Binary = type_
}

pub fn infer_row_test() {
  let scope = []
  let untyped = ast.Row([#("foo", ast.Tuple([]))])
  let Ok(type_) = infer(untyped, scope)
  assert monotype.Row([#("foo", monotype.Tuple([]))], None) = type_
}

pub fn missing_variable_test() {
  let scope = []
  let untyped = ast.Variable("foo")
  assert Error(typer.UnknownVariable("foo")) = infer(untyped, scope)
}

pub fn infer_variable_test() {
  let scope = [#("foo", polytype.Polytype([], monotype.Tuple([])))]
  let untyped = ast.Variable("foo")
  assert Ok(type_) = infer(untyped, scope)
  assert monotype.Tuple([]) = type_
}
