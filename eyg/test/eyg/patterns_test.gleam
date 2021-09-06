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
// pub fn tuple_pattern_test() {
//   let typer = init([])
//   let untyped =
//     ast.let_(
//       pattern.Tuple(["a", "b"]),
//       ast.tuple_([ast.binary(""), ast.tuple_([])]),
//       ast.variable("a"),
//     )
//   let #(typed, typer) = infer(untyped, typer)
//   //   could always resolve within infer fn
//   let State(substitutions: substitutions, ..) = typer
//   let Ok(type_) = get_type(typed)
//   assert monotype.Binary = resolve(type_, substitutions)
// }
// pub fn incorrect_tuple_size_test() {
//   let typer = init([])
//   let untyped =
//     ast.let_(pattern.Tuple(["a"]), ast.tuple_([]), ast.variable("a"))
//   let #(typed, _state) = infer(untyped, typer)
//   let Error(reason) = get_type(typed)
//   let typer.IncorrectArity(1, 0) = reason
// }
// pub fn not_a_tuple_test() {
//   let typer = init([])
//   let untyped =
//     ast.let_(pattern.Tuple(["a"]), ast.binary(""), ast.variable("a"))
//   let #(typed, _state) = infer(untyped, typer)
//   let Error(reason) = get_type(typed)
//   let typer.UnmatchedTypes(monotype.Tuple([_]), monotype.Binary) = reason
// }
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
//   assert monotype.Binary = resolve(type_, substitutions)
// }
// pub fn growing_row_pattern_test() {
//   let typer = init([#("x", polytype.Polytype([], monotype.Unbound(-1)))])
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
//   assert monotype.Tuple([monotype.Unbound(i), monotype.Unbound(j)]) =
//     resolve(type_, substitutions)
//   assert True = i != j
//   assert monotype.Row([a, b], _) = resolve(monotype.Unbound(-1), substitutions)
//   assert #("foo", _) = a
//   assert #("bar", _) = b
// }
// pub fn matched_row_test() {
//   let typer = init([#("x", polytype.Polytype([], monotype.Unbound(-1)))])
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
//   assert monotype.Tuple([monotype.Unbound(i), monotype.Unbound(j)]) =
//     resolve(type_, substitutions)
//   // Tests that the row fields are being resolve
//   assert True = i == j
//   assert monotype.Row([a], _) = resolve(monotype.Unbound(-1), substitutions)
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
