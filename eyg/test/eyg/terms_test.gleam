import gleam/option.{None}
import eyg/ast
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn infer_type_of_tuple_test() {
  let typer = init([])
  let untyped = ast.tuple_([])
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Tuple([]) = get_type(type_)
}

pub fn infer_type_of_nested_tuple_test() {
  let typer = init([])
  let untyped = ast.tuple_([ast.tuple_([])])
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Tuple([monotype.Tuple([])]) = get_type(type_)
}

pub fn infer_binary_test() {
  let typer = init([])
  let untyped = ast.binary("Hello")
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Binary = get_type(type_)
}

pub fn infer_row_test() {
  let typer = init([])
  let untyped = ast.row([#("foo", ast.tuple_([]))])
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Row([#("foo", monotype.Tuple([]))], None) = get_type(type_)
}

pub fn missing_variable_test() {
  let typer = init([])
  let untyped = ast.variable("foo")
  assert Error(#(typer.UnknownVariable("foo"), _state)) = infer(untyped, typer)
}

pub fn infer_variable_test() {
  let typer = init([#("foo", polytype.Polytype([], monotype.Tuple([])))])
  let untyped = ast.variable("foo")
  assert Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Tuple([]) = get_type(type_)
}
// abstraction test
// application test
// let/bind/assignment/pattern_test
