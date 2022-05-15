import gleam/io
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype as t
import eyg/typer/monotype.{resolve}
import eyg/typer/polytype

pub fn type_bound_function_test() {
  let typer = init()
  let scope = typer.root_scope([])
  let untyped = ast.function(p.Tuple([]), ast.binary(""))
  let #(typed, typer) = infer(untyped, t.Unbound(-1), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = get_type(typed)
  assert t.Function(t.Tuple([]), t.Binary) = resolve(type_, substitutions)
}

pub fn generic_function_test() {
  let typer = init()
  let scope = typer.root_scope([])
  let untyped = ast.function(p.Variable("x"), ast.variable("x"))
  let #(typed, typer) = infer(untyped, t.Unbound(-1), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = get_type(typed)
  assert t.Function(t.Unbound(a), t.Unbound(b)) = resolve(type_, substitutions)
  assert True = a == b
}

pub fn call_function_test() {
  let typer = init()
  let scope = typer.root_scope([])
  let untyped =
    ast.call(ast.function(p.Tuple([]), ast.binary("")), ast.tuple_([]))
  let #(typed, typer) = infer(untyped, t.Tuple([]), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = get_type(typed)
  assert t.Tuple([]) = resolve(type_, substitutions)
}

pub fn call_generic_test() {
  let typer = init()
  let scope = typer.root_scope([])
  let untyped =
    ast.call(ast.function(p.Tuple(["x"]), ast.variable("x")), ast.tuple_([]))
  let #(typed, typer) = infer(untyped, t.Tuple([]), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = get_type(typed)
  assert t.Tuple([]) = resolve(type_, substitutions)
}

pub fn call_with_incorrect_argument_test() {
  let typer = init()
  let scope = typer.root_scope([])
  let untyped =
    ast.call(
      ast.function(p.Tuple([]), ast.binary("")),
      ast.tuple_([ast.binary("extra argument")]),
    )
  let #(typed, _state) = infer(untyped, t.Tuple([]), #(typer, scope))
  let #(_context, e.Call(_func, with)) = typed
  assert Error(reason) = get_type(with)
  assert typer.IncorrectArity(0, 1) = reason
}

pub fn reuse_generic_function_test() {
  let typer = init()
  let scope = typer.root_scope([])
  let untyped =
    ast.let_(
      p.Variable("id"),
      ast.function(p.Tuple(["x"]), ast.variable("x")),
      ast.tuple_([
        ast.call(ast.variable("id"), ast.tuple_([])),
        ast.call(ast.variable("id"), ast.binary("")),
      ]),
    )
  let #(typed, typer) =
    infer(untyped, t.Tuple([t.Tuple([]), t.Binary]), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = get_type(typed)
  assert t.Tuple([t.Tuple([]), t.Binary]) = resolve(type_, substitutions)
}
