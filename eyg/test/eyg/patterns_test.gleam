import gleam/io
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/pattern
import eyg/ast/expression
import eyg/typer.{get_type, infer}
import eyg/typer/monotype as t
import eyg/typer/polytype
import platforms/browser

// This is proablbly better called assignment tests, unless it grows too big and patterns should be separate
pub fn variable_of_expected_type_test() {
  let typer = typer.init()
  let scope =
    typer.Scope(
      variables: [#("foo", polytype.Polytype([], t.Tuple([])))],
      path: [],
    )
  let untyped = ast.variable("foo")
  // TODO use analysis.infer in this test file
  assert #(typed, _typer) =
    infer(untyped, t.Tuple([]), t.empty, #(typer, scope))
  assert Ok(t.Tuple([])) = get_type(typed)
}

pub fn variable_of_unexpected_type_test() {
  let typer = typer.init()
  let scope = typer.root_scope([#("foo", polytype.Polytype([], t.Tuple([])))])
  let state = #(typer, scope)
  let untyped = ast.variable("foo")
  assert #(typed, _typer) = infer(untyped, t.Binary, t.empty, state)
  assert Error(reason) = get_type(typed)
  assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = reason
}

pub fn missing_variable_test() {
  let typer = typer.init()
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped = ast.variable("foo")
  let #(typed, _state) = infer(untyped, t.Binary, t.empty, state)
  assert Error(reason) = get_type(typed)
  assert typer.UnknownVariable("foo") = reason
}

// assignment
pub fn expected_assignment_test() {
  let typer = typer.init()
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped =
    ast.let_(pattern.Variable("foo"), ast.tuple_([]), ast.variable("foo"))
  let #(typed, _typer) = infer(untyped, t.Tuple([]), t.empty, state)
  assert Ok(t.Tuple([])) = get_type(typed)
}

pub fn unexpected_then_type_test() {
  let typer = typer.init()
  let scope = typer.root_scope([])
  let state = #(typer, scope)
  let untyped =
    ast.let_(pattern.Variable("foo"), ast.binary("wrong"), ast.variable("foo"))
  let #(typed, _typer) = infer(untyped, t.Tuple([]), t.empty, state)
  //   Should the error be on the inner
  assert Ok(t.Tuple([])) = get_type(typed)
  assert #(_context, expression.Let(_pattern, _value, then)) = typed
  assert Error(reason) = get_type(then)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn matched_expected_tuple_test() {
  let typer = typer.init()
  let scope =
    typer.root_scope([#("foo", polytype.Polytype([], t.Tuple([t.Binary])))])
  let state = #(typer, scope)
  let untyped =
    ast.let_(pattern.Tuple(["a"]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, t.empty, state)
  assert Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = get_type(value)
  assert t.Tuple([t.Binary]) = t.resolve(type_, substitutions)
}

pub fn expected_a_tuple_test() {
  let typer = typer.init()
  let scope = typer.root_scope([#("foo", polytype.Polytype([], t.Binary))])
  let state = #(typer, scope)

  let untyped =
    ast.let_(pattern.Tuple(["a"]), ast.variable("foo"), ast.variable("a"))
  let #(typed, _state) = infer(untyped, t.Binary, t.empty, state)
  assert Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  assert Error(reason) = get_type(value)
  assert typer.UnmatchedTypes(t.Tuple([_]), t.Binary) = reason
}

pub fn unexpected_tuple_size_test() {
  let typer = typer.init()
  let scope = typer.root_scope([#("foo", polytype.Polytype([], t.Tuple([])))])
  let state = #(typer, scope)

  let untyped =
    ast.let_(pattern.Tuple(["a"]), ast.variable("foo"), ast.variable("a"))
  let #(typed, _state) = infer(untyped, t.Binary, t.empty, state)
  assert Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  assert Error(reason) = get_type(value)
  assert typer.IncorrectArity(1, 0) = reason
}

pub fn matched_expected_record_test() {
  let scope =
    typer.root_scope([
      #("foo", polytype.Polytype([], t.Record([#("k", t.Binary)], None))),
    ])
  let state = #(typer.init(), scope)
  let untyped =
    ast.let_(
      pattern.Record([#("k", "a")]),
      ast.variable("foo"),
      ast.variable("a"),
    )
  let #(typed, typer) = infer(untyped, t.Binary, t.empty, state)
  assert Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = get_type(value)
  assert t.Record([#("k", t.Binary)], _) = t.resolve(type_, substitutions)
}

pub fn expected_a_record_test() {
  let typer = typer.init()
  let scope = typer.root_scope([#("foo", polytype.Polytype([], t.Binary))])
  let state = #(typer, scope)

  let untyped =
    ast.let_(
      pattern.Record([#("k", "a")]),
      ast.variable("foo"),
      ast.variable("a"),
    )
  let #(typed, typer) = infer(untyped, t.Binary, t.empty, state)
  assert Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Error(reason) = get_type(value)
  assert typer.UnmatchedTypes(t.Record(_, _), t.Binary) = reason
}

pub fn matched_expected_record_with_additional_fields_test() {
  let scope =
    typer.root_scope([
      #(
        "foo",
        polytype.Polytype(
          [],
          t.Record([#("k", t.Binary), #("j", t.Binary)], None),
        ),
      ),
    ])
  let state = #(typer.init(), scope)
  let untyped =
    ast.let_(
      pattern.Record([#("k", "a")]),
      ast.variable("foo"),
      ast.variable("a"),
    )
  let #(typed, typer) = infer(untyped, t.Binary, t.empty, state)
  assert Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = get_type(value)
  assert t.Record([#("k", t.Binary), _], _) = t.resolve(type_, substitutions)
}

pub fn grow_expected_fields_in_record_test() {
  let typer = typer.init()
  let scope =
    typer.root_scope([#("foo", polytype.Polytype([], t.Record([], Some(-1))))])
  let state = #(typer, scope)

  let untyped =
    ast.let_(
      pattern.Record([#("k", "a")]),
      ast.variable("foo"),
      ast.variable("a"),
    )
  let #(typed, typer) = infer(untyped, t.Binary, t.empty, state)
  assert Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = get_type(value)
  assert t.Record([#("k", t.Binary)], _) = t.resolve(type_, substitutions)
}
