import gleam/io
import eyg/ast
import eyg/ast/expression
import eyg/ast/pattern
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype as t
import eyg/typer/monotype.{resolve}
import eyg/typer/polytype.{State}

pub fn type_bound_function_test() {
  let typer = init([])
  let untyped =
    ast.function(
      "x",
      ast.let_(pattern.Tuple([]), ast.variable("x"), ast.binary("")),
    )
  let #(typed, typer) = infer(untyped, t.Unbound(-1), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Function(t.Tuple([]), t.Binary) = resolve(type_, substitutions)
}

pub fn generic_function_test() {
  let typer = init([])
  let untyped = ast.function("x", ast.variable("x"))
  let #(typed, typer) = infer(untyped, t.Unbound(-1), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Function(t.Unbound(a), t.Unbound(b)) = resolve(type_, substitutions)
  let True = a == b
}

pub fn call_function_test() {
  let typer = init([])
  let untyped =
    ast.call(
      ast.function(
        "x",
        ast.let_(pattern.Tuple([]), ast.variable("x"), ast.binary("")),
      ),
      ast.tuple_([]),
    )
  let #(typed, typer) = infer(untyped, t.Tuple([]), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Tuple([]) = resolve(type_, substitutions)
}

pub fn call_generic_test() {
  let typer = init([])
  let untyped = ast.call(ast.function("x", ast.variable("x")), ast.tuple_([]))
  let #(typed, typer) = infer(untyped, t.Tuple([]), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Tuple([]) = resolve(type_, substitutions)
}

pub fn call_with_incorrect_argument_test() {
  let typer = init([])
  let untyped =
    ast.call(
      ast.function(
        "x",
        ast.let_(pattern.Tuple([]), ast.variable("x"), ast.binary("")),
      ),
      ast.tuple_([ast.binary("extra argument")]),
    )
  let #(typed, _state) = infer(untyped, t.Tuple([]), typer)
  let #(_context, expression.Call(_func, with)) = typed
  let Error(reason) = get_type(with)
  let typer.IncorrectArity(0, 1) = reason
}

pub fn reuse_generic_function_test() {
  let typer = init([])
  let untyped =
    ast.let_(
      pattern.Variable("id"),
      ast.function("x", ast.variable("x")),
      ast.tuple_([
        ast.call(ast.variable("id"), ast.tuple_([])),
        ast.call(ast.variable("id"), ast.binary("")),
      ]),
    )
  let #(typed, typer) = infer(untyped, t.Tuple([t.Tuple([]), t.Binary]), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Tuple([t.Tuple([]), t.Binary]) = resolve(type_, substitutions)
}
