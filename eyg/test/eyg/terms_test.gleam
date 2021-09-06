import gleam/io
import gleam/option.{None}
import eyg/ast
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype as t
import eyg/typer/polytype

pub fn expected_binary_test() {
  let typer = init([])
  let untyped = ast.binary("Hello")
  let #(typed, _typer) = infer(untyped, t.Binary, typer)
  assert Ok(t.Binary) = get_type(typed)
}

pub fn unexpected_binary_error_test() {
  let typer = init([])
  let untyped = ast.binary("Hello")
  let #(typed, _typer) = infer(untyped, t.Tuple([]), typer)
  assert Error(reason) = get_type(typed)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn expected_empty_tuple_test() {
  let typer = init([])
  let untyped = ast.tuple_([])
  let #(typed, _typer) = infer(untyped, t.Tuple([]), typer)
  assert Ok(t.Tuple([])) = get_type(typed)
}

pub fn expected_non_empty_tuple_test() {
  let typer = init([])
  let untyped = ast.tuple_([ast.tuple_([])])
  let #(typed, _typer) = infer(untyped, t.Tuple([t.Tuple([])]), typer)
  assert Ok(t.Tuple([t.Tuple([])])) = get_type(typed)
}

pub fn unexpected_tuple_size_test() {
  let typer = init([])
  let untyped = ast.tuple_([ast.binary("not needed")])
  let #(typed, _typer) = infer(untyped, t.Tuple([]), typer)
  assert Error(reason) = get_type(typed)
  assert typer.IncorrectArity(0, 1) = reason
}

pub fn unexpected_tuple_element_type_test() {
  let typer = init([])
  let untyped = ast.tuple_([ast.binary("Yo")])
  let #(typed, _typer) = infer(untyped, t.Tuple([t.Tuple([])]), typer)
  assert Ok(t.Tuple([t.Tuple([])])) = get_type(typed)
  assert #(_context, ast.Tuple([child])) = typed
  assert Error(reason) = get_type(child)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn expected_row_test() {
  let typer = init([])
  let untyped = ast.row([#("foo", ast.tuple_([]))])
  let #(typed, _typer) =
    infer(untyped, t.Row([#("foo", t.Tuple([]))], None), typer)
  assert Ok(t.Row([#("foo", t.Tuple([]))], None)) = get_type(typed)
}

pub fn unexpected_fields_test() {
  let typer = init([])
  let untyped = ast.row([#("foo", ast.tuple_([]))])
  let #(typed, _typer) = infer(untyped, t.Row([], None), typer)
  assert Error(reason) = get_type(typed)
  assert typer.UnexpectedFields([#("foo", x)]) = reason
  // x is unbound but we probably have better info
}

pub fn missing_fields_test() {
  let typer = init([])
  let untyped = ast.row([])
  let #(typed, _typer) =
    infer(untyped, t.Row([#("foo", t.Tuple([]))], None), typer)
  assert Error(reason) = get_type(typed)
  assert typer.MissingFields([#("foo", x)]) = reason
  // I think we might only need the name not type, BUT why throw away info
}

pub fn unexpected_field_type_test() {
  let typer = init([])
  let untyped = ast.row([#("foo", ast.tuple_([]))])
  let #(typed, _typer) =
    infer(untyped, t.Row([#("foo", t.Binary)], None), typer)
  assert Ok(t.Row([#("foo", t.Binary)], None)) = get_type(typed)
  assert #(_context, ast.Row([#("foo", child)])) = typed
  assert Error(reason) = get_type(child)
  assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) =
}
// pub fn missing_variable_test() {
//   let typer = init([])
//   let untyped = ast.variable("foo")
//   let #(typed, _state) = infer(untyped, typer)
//   let Error(reason) = get_type(typed)
//   assert typer.UnknownVariable("foo") = reason
// }
// pub fn infer_variable_test() {
//   let typer = init([#("foo", polytype.Polytype([], t.Tuple([])))])
//   let untyped = ast.variable("foo")
//   assert #(type_, _typer) = infer(untyped, typer)
//   assert Ok(t.Tuple([])) = get_type(type_)
// }
// // abstraction test
// // application test
// // let/bind/assignment/pattern_test
