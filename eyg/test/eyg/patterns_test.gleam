import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{infer, init}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn assignment_test() {
  let typer = init([])
  let untyped =
    ast.Let(pattern.Variable("foo"), ast.Tuple([]), ast.Variable("foo"))
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Tuple([]) = type_
}
