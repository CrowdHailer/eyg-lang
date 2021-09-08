import gleam/option.{None}
import eyg/ast
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn infer_type_of_tuple_test() {
  let typer = init([])
  let untyped = ast.tuple_([])
  let #(type_, _typer) = infer(untyped, typer)
  assert Ok(monotype.Tuple([])) = get_type(type_)
}

pub fn infer_type_of_nested_tuple_test() {
  let typer = init([])
  let untyped = ast.tuple_([ast.tuple_([])])
  let #(type_, _typer) = infer(untyped, typer)
  assert Ok(monotype.Tuple([monotype.Tuple([])])) = get_type(type_)
}

pub fn infer_binary_test() {
  let typer = init([])
  let untyped = ast.binary("Hello")
  let #(type_, _typer) = infer(untyped, typer)
  assert Ok(monotype.Binary) = get_type(type_)
}

pub fn infer_row_test() {
  let typer = init([])
  let untyped = ast.row([#("foo", ast.tuple_([]))])
  let #(type_, _typer) = infer(untyped, typer)
  assert Ok(monotype.Row([#("foo", monotype.Tuple([]))], None)) =
    get_type(type_)
}

pub fn missing_variable_test() {
  let typer = init([])
  let untyped = ast.variable("foo")
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnknownVariable("foo") = reason
}

pub fn infer_variable_test() {
  let typer = init([#("foo", polytype.Polytype([], monotype.Tuple([])))])
  let untyped = ast.variable("foo")
  assert #(type_, _typer) = infer(untyped, typer)
  assert Ok(monotype.Tuple([])) = get_type(type_)
}
// abstraction test
// application test
// let/bind/assignment/pattern_test
