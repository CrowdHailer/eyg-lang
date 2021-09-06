import gleam/io
import eyg/ast
import eyg/ast/pattern
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
  assert #(_context, ast.Let(_pattern, _value, then)) = typed
  assert Error(reason) = get_type(then)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn matched_expected_tuple_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Tuple([t.Binary])))])
  let untyped =
    ast.let_(pattern.Tuple(["a"]), ast.variable("foo"), ast.variable("a"))
  let #(typed, typer) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, ast.Let(_pattern, _value, then)) = typed
  let Ok(t.Binary) = get_type(then)
}

pub fn expected_a_tuple_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Binary))])

  let untyped =
    ast.let_(pattern.Tuple(["a"]), ast.variable("foo"), ast.variable("a"))
  let #(typed, _state) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, ast.Let(_pattern, value, _then)) = typed
  let Error(reason) = get_type(value)
  let typer.UnmatchedTypes(t.Tuple([_]), t.Binary) = reason
}

pub fn unexpected_tuple_size_test() {
  let typer = init([#("foo", polytype.Polytype([], t.Tuple([])))])

  let untyped =
    ast.let_(pattern.Tuple(["a"]), ast.variable("foo"), ast.variable("a"))
  let #(typed, _state) = infer(untyped, t.Binary, typer)
  let Ok(t.Binary) = get_type(typed)
  assert #(_context, ast.Let(_pattern, value, _then)) = typed
  let Error(reason) = get_type(value)
  let typer.IncorrectArity(1, 0) = reason
}
// pub fn matching_row_test() {
//   let typer = init([])
//   let untyped =
//     ast.let_(
//       pattern.Row([#("foo", "a")]),
//       ast.row([#("foo", ast.binary(""))]),
//       ast.variable("a"),
//     )
//   let #(typed, typer) = infer(untyped, typer)
//   let State(substitutions: substitutions, ..) = typer
//   let Ok(type_) = get_type(typed)
//   assert t.Binary = resolve(type_, substitutions)
// }
// pub fn growing_row_pattern_test() {
//   let typer = init([#("x", polytype.Polytype([], t.Unbound(-1)))])
//   let untyped =
//     ast.let_(
//       pattern.Row([#("foo", "a")]),
//       ast.variable("x"),
//       ast.let_(
//         pattern.Row([#("bar", "b")]),
//         ast.variable("x"),
//         ast.tuple_([ast.variable("a"), ast.variable("b")]),
//       ),
//     )
//   let #(typed, typer) = infer(untyped, typer)
//   let State(substitutions: substitutions, ..) = typer
//   let Ok(type_) = get_type(typed)
//   assert t.Tuple([t.Unbound(i), t.Unbound(j)]) =
//     resolve(type_, substitutions)
//   assert True = i != j
//   assert t.Row([a, b], _) = resolve(t.Unbound(-1), substitutions)
//   assert #("foo", _) = a
//   assert #("bar", _) = b
// }
// pub fn matched_row_test() {
//   let typer = init([#("x", polytype.Polytype([], t.Unbound(-1)))])
//   let untyped =
//     ast.let_(
//       pattern.Row([#("foo", "a")]),
//       ast.variable("x"),
//       ast.let_(
//         pattern.Row([#("foo", "b")]),
//         ast.variable("x"),
//         ast.tuple_([ast.variable("a"), ast.variable("b")]),
//       ),
//     )
//   let #(typed, typer) = infer(untyped, typer)
//   let State(substitutions: substitutions, ..) = typer
//   let Ok(type_) = get_type(typed)
//   assert t.Tuple([t.Unbound(i), t.Unbound(j)]) =
//     resolve(type_, substitutions)
//   // Tests that the row fields are being resolve
//   assert True = i == j
//   assert t.Row([a], _) = resolve(t.Unbound(-1), substitutions)
//   assert #("foo", _) = a
// }
// pub fn missing_row_test() {
//   let typer = init([])
//   let untyped =
//     ast.let_(pattern.Row([#("foo", "a")]), ast.row([]), ast.variable("a"))
//   let #(typed, _state) = infer(untyped, typer)
//   let Error(reason) = get_type(typed)
//   let typer.MissingFields(extra) = reason
//   let [#("foo", _)] = extra
// }
// // Have resolved as a type wrapper
