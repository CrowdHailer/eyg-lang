import gleam/io
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/pattern
import eyg/ast/expression
import eyg/typer.{get_type, infer}
import eyg/typer/monotype as t
import eyg/typer/polytype
import platform/browser

pub fn matched_expected_row_test() {
  let scope =
    typer.root_scope([
      #("foo", polytype.Polytype([], t.Row([#("k", t.Binary)], None))),
    ])
  let state = #(typer.init(browser.native_to_string), scope)
  let untyped =
    ast.let_(pattern.Row([#("k", "a")]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, state)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let typer.Typer(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(value)
  let t.Row([#("k", t.Binary)], _) = t.resolve(type_, substitutions)
}

pub fn expected_a_row_test() {
  let typer = typer.init(browser.native_to_string)
  let scope = typer.root_scope([#("foo", polytype.Polytype([], t.Binary))])
  let state = #(typer, scope)

  let untyped =
    ast.let_(pattern.Row([#("k", "a")]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, state)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let typer.Typer(substitutions: substitutions, ..) = typer
  let Error(reason) = get_type(value)
  let typer.UnmatchedTypes(t.Row(_, _), t.Binary) = reason
}

pub fn matched_expected_row_with_additional_fields_test() {
  let scope =
    typer.root_scope([
      #(
        "foo",
        polytype.Polytype([], t.Row([#("k", t.Binary), #("j", t.Binary)], None)),
      ),
    ])
  let state = #(typer.init(browser.native_to_string), scope)
  let untyped =
    ast.let_(pattern.Row([#("k", "a")]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, state)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let typer.Typer(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(value)
  let t.Row([#("k", t.Binary), _], _) = t.resolve(type_, substitutions)
}

pub fn grow_expected_fields_in_row_test() {
  let typer = typer.init(browser.native_to_string)
  let scope =
    typer.root_scope([#("foo", polytype.Polytype([], t.Row([], Some(-1))))])
  let state = #(typer, scope)

  let untyped =
    ast.let_(pattern.Row([#("k", "a")]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, state)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, expression.Let(_pattern, value, _then)) = typed
  let typer.Typer(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(value)
  let t.Row([#("k", t.Binary)], _) = t.resolve(type_, substitutions)
}
