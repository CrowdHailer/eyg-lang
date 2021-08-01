import gleam/io
import language/ast/builder.{binary, call, function, let_, var}
import language/ast
import language/type_.{CouldNotUnify, IncorrectArity}
import language/scope
import language/type_.{Data, Function, Variable}
import language/ast/support

pub fn infer_identity_function_test() {
  let untyped = function(["x"], var("x"))
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  let Function([Variable(a)], Variable(b)) = type_.resolve_type(type_, typer)
  let True = a == b
}

pub fn infer_call_test() {
  let untyped = call(function([], binary()), [])
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn infer_call_with_arguments_test() {
  let untyped = call(function(["x"], var("x")), [binary()])
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  io.debug(typer)
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn generic_functions_test() {
  let identity = function(["x"], var("x"))
  let untyped =
    let_(
      "id",
      identity,
      let_("temp", call(var("id"), [var("id")]), call(var("temp"), [binary()])),
    )

  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn incorrect_arity_test() {
  let scope =
    scope.new()
    |> support.with_equal()

  // Test that number of args is the first error
  let too_many_args =
    call(var("equal"), [call(var("True"), []), binary(), binary()])
  let Error(IncorrectArity(expected: 2, given: 3)) =
    ast.infer(too_many_args, scope)

  let too_few_args = call(var("equal"), [binary()])
  let Error(IncorrectArity(expected: 2, given: 1)) =
    ast.infer(too_few_args, scope)

  // Test for data constructors
  let too_many_args = call(var("True"), [binary()])
  let Error(IncorrectArity(expected: 0, given: 1)) =
    ast.infer(too_many_args, scope)
}

pub fn call_argument_mistype_test() {
  let scope =
    scope.new()
    |> support.with_equal()

  let too_few_args = call(var("equal"), [binary(), call(var("True"), [])])
  let Error(CouldNotUnify(
    expected: Data("Binary", []),
    given: Data("Boolean", []),
  )) = ast.infer(too_few_args, scope)
}
