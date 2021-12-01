import gleam/io
import gleam/option.{Some}
import eyg/ast
import eyg/ast/expression
import eyg/ast/pattern
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype as t
import eyg/typer/monotype.{resolve}
import eyg/typer/polytype.{State}

pub fn type_bound_function_test() {
  let typer = init([])
  let untyped = ast.function(pattern.Tuple([]), ast.binary(""))
  let #(typed, typer) = infer(untyped, t.Unbound(-1), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Function(t.Tuple([]), t.Binary) = resolve(type_, substitutions)
}

pub fn generic_function_test() {
  let typer = init([])
  let untyped = ast.function(pattern.Variable("x"), ast.variable("x"))
  let #(typed, typer) = infer(untyped, t.Unbound(-1), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Function(t.Unbound(a), t.Unbound(b)) = resolve(type_, substitutions)
  let True = a == b
}

pub fn call_function_test() {
  let typer = init([])
  let untyped =
    ast.call(ast.function(pattern.Tuple([]), ast.binary("")), ast.tuple_([]))
  let #(typed, typer) = infer(untyped, t.Tuple([]), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Tuple([]) = resolve(type_, substitutions)
}

pub fn call_generic_test() {
  let typer = init([])
  let untyped =
    ast.call(
      ast.function(pattern.Tuple([Some("x")]), ast.variable("x")),
      ast.tuple_([]),
    )
  let #(typed, typer) = infer(untyped, t.Tuple([]), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Tuple([]) = resolve(type_, substitutions)
}

pub fn call_with_incorrect_argument_test() {
  let typer = init([])
  let untyped =
    ast.call(
      ast.function(pattern.Tuple([]), ast.binary("")),
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
      ast.function(pattern.Tuple([Some("x")]), ast.variable("x")),
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

pub fn recursive_type_test() {
  let typer = init([])
  let untyped = // ast.function(
    //   pattern.Variable("f"),
    //   ast.call(
    //     ast.variable("self"),
    //     ast.call(ast.variable("f"), ast.tuple_([])),
    //   ),
    // )
    ast.let_(
      pattern.Variable("Cons"),
      ast.function(
        pattern.Tuple([Some("head"), Some("tail")]),
        ast.function(
          pattern.Row([#("Cons", "then")]),
          ast.call(
            ast.variable("then"),
            ast.tuple_([ast.variable("head"), ast.variable("tail")]),
          ),
        ),
      ),
      ast.let_(
        pattern.Variable("Nil"),
        ast.function(
          pattern.Row([#("Nil", "then")]),
          ast.call(ast.variable("then"), ast.tuple_([])),
        ),
        ast.let_(
          pattern.Variable("reverse"),
          ast.function(
            pattern.Tuple([Some("remaining"), Some("accumulator")]),
            ast.call(
              ast.variable("remaining"),
              ast.row([
                #("Cons", ast.call(ast.variable("Cons"), ast.tuple_([]))),
                #(
                  "Nin",
                  ast.function(pattern.Tuple([]), ast.variable("remaining")),
                ),
              ]),
            ),
          ),
          ast.variable("reverse"),
        ),
      ),
    )

  let #(typed, typer) = infer(untyped, t.Unbound(-1), typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Function(t.Tuple([]), t.Binary) = resolve(type_, substitutions)
}
