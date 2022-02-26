import gleam/io
import gleam/option.{None}
import eyg
import eyg/ast
import eyg/ast/expression
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype as t
import eyg/typer/polytype

pub fn expected_binary_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.binary("Hello")
  let #(typed, _typer) = infer(untyped, t.Binary, state)
  assert Ok(t.Binary) = get_type(typed)
}

pub fn unexpected_binary_error_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.binary("Hello")
  let #(typed, _typer) = infer(untyped, t.Tuple([]), state)
  assert Error(reason) = get_type(typed)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn expected_empty_tuple_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.tuple_([])
  let #(typed, _typer) = infer(untyped, t.Tuple([]), state)
  assert Ok(t.Tuple([])) = get_type(typed)
}

pub fn expected_non_empty_tuple_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.tuple_([ast.tuple_([])])
  let #(typed, _typer) = infer(untyped, t.Tuple([t.Tuple([])]), state)
  assert Ok(t.Tuple([t.Tuple([])])) = get_type(typed)
}

pub fn unexpected_tuple_size_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.tuple_([ast.binary("not needed")])
  let #(typed, _typer) = infer(untyped, t.Tuple([]), state)
  assert Error(reason) = get_type(typed)
  assert typer.IncorrectArity(0, 1) = reason
}

pub fn unexpected_tuple_element_type_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.tuple_([ast.binary("Yo")])
  let #(typed, _typer) = infer(untyped, t.Tuple([t.Tuple([])]), state)
  assert Ok(t.Tuple([t.Tuple([])])) = get_type(typed)
  assert #(_context, expression.Tuple([child])) = typed
  assert Error(reason) = get_type(child)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn expected_row_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.row([#("foo", ast.tuple_([]))])
  let #(typed, _typer) =
    infer(untyped, t.Record([#("foo", t.Tuple([]))], None), state)
  assert Ok(t.Record([#("foo", t.Tuple([]))], None)) = get_type(typed)
}

pub fn unexpected_fields_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.row([#("foo", ast.tuple_([]))])
  let #(typed, _typer) = infer(untyped, t.Record([], None), state)
  assert Error(reason) = get_type(typed)
  assert typer.UnexpectedFields([#("foo", x)]) = reason
  // x is unbound but we probably have better info
}

pub fn missing_fields_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.row([])
  let #(typed, _typer) =
    infer(untyped, t.Record([#("foo", t.Tuple([]))], None), state)
  assert Error(reason) = get_type(typed)
  assert typer.MissingFields([#("foo", x)]) = reason
  // I think we might only need the name not type, BUT why throw away info
}

pub fn unexpected_field_type_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.row([#("foo", ast.tuple_([]))])
  let #(typed, _typer) =
    infer(untyped, t.Record([#("foo", t.Binary)], None), state)
  assert Ok(t.Record([#("foo", t.Binary)], None)) = get_type(typed)
  assert #(_context, expression.Record([#("foo", child)])) = typed
  assert Error(reason) = get_type(child)
  assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = reason
}
