import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{infer, init, resolve}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn typed_function_test() {
  let typer = init([])
  let untyped =
    ast.Function(
      "x",
      ast.Let(pattern.Tuple([]), ast.Variable("x"), ast.Binary("")),
    )
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let monotype.Function(monotype.Tuple([]), monotype.Binary) =
    resolve(type_, typer)
}

pub fn generic_function_test() {
  let typer = init([])
  let untyped = ast.Function("x", ast.Variable("x"))
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let monotype.Function(monotype.Unbound(a), monotype.Unbound(b)) =
    resolve(type_, typer)
  let True = a == b
}
