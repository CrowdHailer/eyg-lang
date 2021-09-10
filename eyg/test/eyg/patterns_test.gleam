import gleam/io
import gleam/option.{None, Some}
import eyg/ast
import eyg/ast/pattern
import eyg/ast/expression
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype as t
import eyg/typer/polytype.{State}

// This is proablbly better called assignment tests, unless it grows too big and patterns should be separate
pub fn variable_of_expected_type_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Tuple([])))])
  let untyped = ast.variable("foo")
  assert #(typed, _typer) = infer(untyped, t.Tuple([]), typer)
  assert Ok(t.Tuple([])) = get_type(typed)
}

pub fn variable_of_unexpected_type_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Tuple([])))])
  let untyped = ast.variable("foo")
  assert #(typed, _typer) = infer(untyped, t.Binary, typer)
  assert Error(reason) = get_type(typed)
  assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = reason
}

pub fn missing_variable_test() {
  let typer = init([])
  let untyped = ast.variable("foo")
  let #(typed, _state) = infer(untyped, t.Binary, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnknownVariable("foo") = reason
}

// assignment
pub fn expected_assignment_test() {
  let typer = init([])
  let untyped =
    ast.let_(pattern.Variable("foo"), ast.tuple_([]), ast.variable("foo"))
  let #(typed, _typer) = infer(untyped, t.Tuple([]), typer)
  assert Ok(t.Tuple([])) = get_type(typed)
}

pub fn unexpected_then_type_test() {
  let typer = init([])
  let untyped =
    ast.let_(pattern.Variable("foo"), ast.binary("wrong"), ast.variable("foo"))
  let #(typed, _typer) = infer(untyped, t.Tuple([]), typer)
  //   Should the error be on the inner
  assert Ok(t.Tuple([])) = get_type(typed)
  assert #(_context, expression.Let(_pattern, _value, then)) = typed
  assert Error(reason) = get_type(then)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn matched_expected_tuple_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Tuple([t.Binary])))])
  let untyped =
    ast.let_(pattern.Tuple(["a"]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(value)
  let t.Tuple([t.Binary]) = t.resolve(type_, substitutions)
}

pub fn expected_a_tuple_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Binary))])

  let untyped =
    ast.let_(pattern.Tuple(["a"]), ast.variable("foo"), ast.variable("a"))
  let #(typed, _state) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let Error(reason) = get_type(value)
  let typer.UnmatchedTypes(t.Tuple([_]), t.Binary) = reason
}

pub fn unexpected_tuple_size_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Tuple([])))])

  let untyped =
    ast.let_(pattern.Tuple(["a"]), ast.variable("foo"), ast.variable("a"))
  let #(typed, _state) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let Error(reason) = get_type(value)
  let typer.IncorrectArity(1, 0) = reason
}

pub fn matched_expected_row_test() {
  let typer =
    init([#("foo", polytype.Polytype([], t.Row([#("k", t.Binary)], None)))])

  let untyped =
    ast.let_(pattern.Row([#("k", "a")]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(value)
  let t.Row([#("k", t.Binary)], _) = t.resolve(type_, substitutions)
}

pub fn expected_a_row_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Binary))])

  let untyped =
    ast.let_(pattern.Row([#("k", "a")]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let State(substitutions: substitutions, ..) = typer
  let Error(reason) = get_type(value)
  let typer.UnmatchedTypes(t.Row(_, _), t.Binary) = reason
}

pub fn matched_expected_row_with_additional_fields_test() {
  let typer =
    init([
      #(
        "foo",
        polytype.Polytype([], t.Row([#("k", t.Binary), #("j", t.Binary)], None)),
      ),
    ])

  let untyped =
    ast.let_(pattern.Row([#("k", "a")]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(value)
  let t.Row([#("k", t.Binary), _], _) = t.resolve(type_, substitutions)
}

pub fn grow_expected_fields_in_row_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Row([], Some(-1))))])

  let untyped =
    ast.let_(pattern.Row([#("k", "a")]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(value)
  let t.Row([#("k", t.Binary)], _) = t.resolve(type_, substitutions)
}
