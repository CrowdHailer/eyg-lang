import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{infer, init, resolve}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn assignment_test() {
  let typer = init([])
  let untyped =
    ast.Let(pattern.Variable("foo"), ast.Tuple([]), ast.Variable("foo"))
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Tuple([]) = type_
}

pub fn tuple_pattern_test() {
  let typer = init([])
  let untyped =
    ast.Let(
      pattern.Tuple(["a"]),
      ast.Tuple([ast.Binary("")]),
      ast.Variable("a"),
    )
  let Ok(#(type_, typer)) = infer(untyped, typer)
  //   could always resolve within infer fn
  assert monotype.Binary = resolve(type_, typer)
}

pub fn incorrect_tuple_size_test() {
  let typer = init([])
  let untyped = ast.Let(pattern.Tuple(["a"]), ast.Tuple([]), ast.Variable("a"))
  let Error(typer.IncorrectArity(1, 0)) = infer(untyped, typer)
}

pub fn not_a_tuple_test() {
  let typer = init([])
  let untyped = ast.Let(pattern.Tuple(["a"]), ast.Binary(""), ast.Variable("a"))
  let Error(typer.UnmatchedTypes(monotype.Tuple([_]), monotype.Binary)) =
    infer(untyped, typer)
}
