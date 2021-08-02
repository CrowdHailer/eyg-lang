import language/ast/builder.{binary, call, destructure, let_, var}
import language/ast.{ValueDestructuring}
import language/type_.{CouldNotUnify, IncorrectArity, UnknownVariable}
import language/scope
import language/type_.{Data}
import language/ast/support

pub fn infer_type_constructor_for_var_test() {
  let untyped = let_("foo", binary(), var("foo"))
  let Ok(#(type_, _, _)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Data("Binary", []) = type_
}

pub fn missing_var_test() {
  let untyped = var("bar")
  let Error(#(failure, situation)) = ast.infer(untyped, scope.new())

  let UnknownVariable("bar") = failure
}

pub fn destructure_test() {
  let scope =
    scope.new()
    |> scope.newtype("User", [], [#("User", [Data("Binary", [])])])

  let untyped =
    destructure(
      "User",
      ["first_name"],
      call(var("User"), [binary()]),
      var("first_name"),
    )
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn unknown_constructor_test() {
  let untyped = destructure("True", [], binary(), binary())
  let Error(#(UnknownVariable("True"), _situation)) =
    ast.infer(untyped, scope.new())
}

pub fn incorrect_destructure_arity_test() {
  let scope =
    scope.new()
    |> scope.newtype("User", [], [#("User", [Data("Binary", [])])])

  let untyped = destructure("User", [], call(var("User"), [binary()]), binary())
  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let IncorrectArity(expected: 1, given: 0) = failure
  let ValueDestructuring("User") = situation
}

pub fn incorrect_destructure_type_test() {
  let scope =
    scope.new()
    |> scope.newtype("User", [], [#("User", [Data("Binary", [])])])
    |> support.with_equal()

  let untyped = destructure("True", [], call(var("User"), [binary()]), binary())
  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let CouldNotUnify(expected: Data("User", []), given: Data("Boolean", [])) =
    failure
  let ValueDestructuring("True") = situation
}
