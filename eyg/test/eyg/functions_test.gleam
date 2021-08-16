import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{infer, init}
import eyg/typer/monotype.{resolve}
import eyg/typer/polytype.{State}

pub fn typed_function_test() {
  let typer = init([])
  let untyped =
    ast.Function(
      "x",
      ast.Let(pattern.Tuple([]), ast.Variable("x"), ast.Binary("")),
    )
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer

  let monotype.Function(monotype.Tuple([]), monotype.Binary) =
    resolve(type_, substitutions)
}

pub fn generic_function_test() {
  let typer = init([])
  let untyped = ast.Function("x", ast.Variable("x"))
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer

  let monotype.Function(monotype.Unbound(a), monotype.Unbound(b)) =
    resolve(type_, substitutions)
  let True = a == b
}

pub fn call_function_test() {
  let typer = init([])
  let untyped =
    ast.Call(
      ast.Function(
        "x",
        ast.Let(pattern.Tuple([]), ast.Variable("x"), ast.Binary("")),
      ),
      ast.Tuple([]),
    )
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer

  let monotype.Binary = resolve(type_, substitutions)
}

pub fn call_generic_test() {
  let typer = init([])
  let untyped = ast.Call(ast.Function("x", ast.Variable("x")), ast.Tuple([]))
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer

  let monotype.Tuple([]) = resolve(type_, substitutions)
}

pub fn call_with_incorrect_argument_test() {
  let typer = init([])
  let untyped =
    ast.Call(
      ast.Function(
        "x",
        ast.Let(pattern.Tuple([]), ast.Variable("x"), ast.Binary("")),
      ),
      ast.Tuple([ast.Binary("extra argument")]),
    )
  let Error(typer.IncorrectArity(0, 1)) = infer(untyped, typer)
}

pub fn reuse_generic_function_test() {
  let typer = init([])
  let untyped =
    ast.Let(
      pattern.Variable("id"),
      ast.Function("x", ast.Variable("x")),
      ast.Tuple([
        ast.Call(ast.Variable("id"), ast.Tuple([])),
        ast.Call(ast.Variable("id"), ast.Binary("")),
      ]),
    )
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer

  let monotype.Tuple([monotype.Tuple([]), monotype.Binary]) =
    resolve(type_, substitutions)
}
