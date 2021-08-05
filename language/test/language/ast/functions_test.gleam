import gleam/io
import language/ast/builder.{binary, call, case_, function, let_, var}
import language/ast.{Destructure, FunctionCall}
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
  let untyped = call(function([], binary("abc")), [])
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn infer_call_with_arguments_test() {
  let untyped = call(function(["x"], var("x")), [binary("abc")])
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn generic_functions_test() {
  let identity = function(["x"], var("x"))
  let untyped =
    let_(
      "id",
      identity,
      let_(
        "temp",
        call(var("id"), [var("id")]),
        call(var("temp"), [binary("abc")]),
      ),
    )

  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn recursion_test() {
  let scope =
    scope.new()
    |> scope.newtype("Option", [1], [#("None", []), #("Some", [Variable(1)])])
  let untyped =
    function(
      ["x"],
      case_(
        var("x"),
        [
          #(
            Destructure("Some", ["value"]),
            call(var("self"), [call(var("None"), [])]),
          ),
          #(Destructure("None", []), binary("abc")),
        ],
      ),
    )
  // recur as a keyword same as clojure
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Function([input], return) = type_.resolve_type(type_, typer)
}

pub fn generalising_restricted_by_scope_test() {
  let scope =
    scope.new()
    |> support.with_equal()
  let untyped =
    // make matcher function
    let_(
      "make_match",
      function(
        ["text"],
        function(["x"], call(var("equal"), [var("text"), var("x")])),
      ),
      call(var("make_match"), [binary("abc")]),
    )

  // make match is a fn type that should Not be generalised
  // isolated let etc can there be a whole that get's the scope
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Function([Data("Binary", [])], Data("Boolean", [])) =
    type_.resolve_type(type_, typer)
}

pub fn incorrect_arity_test() {
  let scope =
    scope.new()
    |> support.with_equal()

  // Test that number of args is the first error
  let too_many_args =
    call(var("equal"), [call(var("True"), []), binary("abc"), binary("abc")])
  let Error(#(failure, situation)) = ast.infer(too_many_args, scope)
  let IncorrectArity(expected: 2, given: 3) = failure
  let FunctionCall = situation

  let too_few_args = call(var("equal"), [binary("abc")])
  let Error(#(failure, situation)) = ast.infer(too_few_args, scope)
  let IncorrectArity(expected: 2, given: 1) = failure
  let FunctionCall = situation

  // Test for data constructors
  let too_many_args = call(var("True"), [binary("abc")])
  let Error(#(failure, situation)) = ast.infer(too_many_args, scope)
  let IncorrectArity(expected: 0, given: 1) = failure
  let FunctionCall = situation
}

pub fn call_argument_mistype_test() {
  let scope =
    scope.new()
    |> support.with_equal()

  let too_few_args = call(var("equal"), [binary("abc"), call(var("True"), [])])
  let Error(#(failure, situation)) = ast.infer(too_few_args, scope)
  let CouldNotUnify(expected: Data("Binary", []), given: Data("Boolean", [])) =
    failure
  let FunctionCall = situation
}
