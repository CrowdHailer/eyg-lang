import gleam/io
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype

fn infer(untyped, type_) {
  let native_to_string = fn(_: Nil) { "" }
  let variables = [#("equal", typer.equal_fn())]
  let checker = typer.init(native_to_string)
  let scope = typer.root_scope(variables)
  let state = #(checker, scope)
  typer.infer(untyped, type_, state)
}

fn get_type(typed, checker: typer.Typer(n)) {
  case typer.get_type(typed) {
    Ok(type_) -> Ok(t.resolve(type_, checker.substitutions))
    Error(reason) -> todo("resolve")
  }
}

pub fn case_test() {
  let source =
    e.function(
      p.Variable("x"),
      e.case_(
        e.variable("x"),
        [
          #("None", p.Tuple([]), e.binary("fallback")),
          #("Some", p.Variable("a"), e.variable("a")),
        ],
      ),
    )

  let #(typed, checker) = infer(source, t.Unbound(-1))
  assert Ok(t.Function(from, to)) = get_type(typed, checker)
  assert [] = checker.inconsistencies
  assert t.Union([#("None", t.Tuple([])), #("Some", t.Binary)], None) = from
  assert t.Binary = to

  let expected =
    t.Function(t.Union([#("None", t.Tuple([]))], Some(-1)), t.Binary)
  let #(typed, checker) = infer(source, expected)
  assert [] = checker.inconsistencies
  assert Ok(t.Function(from, to)) = get_type(typed, checker)
  //   This remains a limited type because it's only on instantiation within the case value that it get's unified
  assert t.Union([#("None", t.Tuple([])), #("Some", t.Binary)], Some(_)) = from
  assert t.Binary = to

  let expected =
    t.Function(t.Union([#("Foo", t.Tuple([]))], Some(-1)), t.Binary)
  let #(typed, checker) = infer(source, expected)
  assert [#(path, error)] = checker.inconsistencies
  // body of function, value of case
  assert [1, 0] = path
  assert typer.UnexpectedFields([#("Foo", t.Tuple([]))]) = error

  let expected =
    t.Function(t.Union([#("Some", t.Tuple([]))], Some(-1)), t.Binary)
  let #(typed, checker) = infer(source, expected)
  assert [#(path, error)] = checker.inconsistencies
  // then of second branch
  assert [1, 2, 2] = path
  assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = error
}
