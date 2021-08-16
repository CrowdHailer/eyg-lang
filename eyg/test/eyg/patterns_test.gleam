import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{infer}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn assignment_test() {
  let scope = []
  let untyped =
    ast.Let(pattern.Variable("foo"), ast.Tuple([]), ast.Variable("foo"))
  let Ok(type_) = infer(untyped, scope)
  assert monotype.Tuple([]) = type_
}

pub fn tuple_pattern_test() {
  let scope = []
  let untyped =
    ast.Let(
      pattern.Tuple(["a"]),
      ast.Tuple([ast.Binary("")]),
      ast.Variable("a"),
    )
  let Ok(type_) = infer(untyped, scope)
  //   could always resolve within infer fn
  assert monotype.Binary = type_
}

pub fn incorrect_tuple_size_test() {
  let scope = []
  let untyped = ast.Let(pattern.Tuple(["a"]), ast.Tuple([]), ast.Variable("a"))
  let Error(typer.IncorrectArity(1, 0)) = infer(untyped, scope)
}

pub fn not_a_tuple_test() {
  let scope = []
  let untyped = ast.Let(pattern.Tuple(["a"]), ast.Binary(""), ast.Variable("a"))
  let Error(typer.UnmatchedTypes(monotype.Tuple([_]), monotype.Binary)) =
    infer(untyped, scope)
}

pub fn matching_row_test() {
  let scope = []
  let untyped =
    ast.Let(
      pattern.Row([#("foo", "a")]),
      ast.Row([#("foo", ast.Binary(""))]),
      ast.Variable("a"),
    )
  let Ok(type_) = infer(untyped, scope)
  assert monotype.Binary = type_
}

pub fn growing_row_pattern_test() {
  let scope = [#("x", polytype.Polytype([], monotype.Unbound(-1)))]
  let untyped =
    ast.Let(
      pattern.Row([#("foo", "a")]),
      ast.Variable("x"),
      ast.Let(
        pattern.Row([#("bar", "b")]),
        ast.Variable("x"),
        ast.Tuple([ast.Variable("a"), ast.Variable("b")]),
      ),
    )
  io.debug("infering")
  let Ok(type_) = infer(untyped, scope)
  io.debug("infered")

  assert monotype.Tuple([monotype.Unbound(i), monotype.Unbound(j)]) = type_
  assert True = i != j
  todo("put this back in")
  // assert monotype.Row([a, b], _) = resolve(monotype.Unbound(-1), typer)
  // assert #("foo", _) = a
  // assert #("bar", _) = b
}

pub fn matched_row_test() {
  let scope = [#("x", polytype.Polytype([], monotype.Unbound(-1)))]
  let untyped =
    ast.Let(
      pattern.Row([#("foo", "a")]),
      ast.Variable("x"),
      ast.Let(
        pattern.Row([#("foo", "b")]),
        ast.Variable("x"),
        ast.Tuple([ast.Variable("a"), ast.Variable("b")]),
      ),
    )
  let Ok(type_) = infer(untyped, scope)

  assert monotype.Tuple([monotype.Unbound(i), monotype.Unbound(j)]) = type_
  // Tests that the row fields are being resolve
  assert True = i == j
  todo("put this back in")
  // assert monotype.Row([a], _) = resolve(monotype.Unbound(-1), typer)
  // assert #("foo", _) = a
}

pub fn missing_row_test() {
  let scope = []
  let untyped =
    ast.Let(pattern.Row([#("foo", "a")]), ast.Row([]), ast.Variable("a"))
  let Error(typer.MissingFields(extra)) = infer(untyped, scope)
  let [#("foo", _)] = extra
}
// Have resolved as a type wrapper
