import language/ast/builder.{binary, call, destructure, let_, var, function, case_}
import language/ast.{ValueDestructuring, Destructure, CaseClause, Assignment}
import language/type_.{
  CouldNotUnify, IncorrectArity, UnhandledVarients, UnknownVariable, RedundantClause,
}
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

pub fn multvariant_let_error_test() {
  let scope =
    scope.new()
    |> support.with_equal()
  let untyped =
    destructure("True", [], call(var("equal"), [binary(), binary()]), binary())
  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let UnhandledVarients(["False"]) = failure
  let ValueDestructuring("True") = situation
}

pub fn missing_case_error_test() {
  let scope =
    scope.new()
    |> scope.newtype("Foo", [], [#("A", []), #("B", []), #("C", [])])

  let untyped =
    function(
      ["x"],
      case_(
        var("x"),
        [
          #(Destructure("A", []), binary()),
          #(Destructure("B", []), binary()),
        ],
      ),
    )

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let UnhandledVarients(["C"]) = failure
  let CaseClause = situation
}


pub fn duplicate_case_error_test() {
  let scope =
    scope.new()
    |> scope.newtype("Foo", [], [#("A", []), #("B", []), #("C", [])])

  let untyped =
    function(
      ["x"],
      case_(
        var("x"),
        [
          #(Destructure("A", []), binary()),
          #(Destructure("A", []), binary()),
        ],
      ),
    )

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let RedundantClause("A") = failure
  let CaseClause = situation
}

pub fn following_catch_all_error_test() {
  let scope =
    scope.new()
    |> scope.newtype("Foo", [], [#("A", []), #("B", []), #("C", [])])

  let untyped =
    function(
      ["x"],
      case_(
        var("x"),
        [
          #(Destructure("A", []), binary()),
          #(Assignment("foo"), binary()),
          #(Destructure("B", []), binary()),
        ],
      ),
    )

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let RedundantClause("B") = failure
  let CaseClause = situation
}

pub fn duplicate_catch_all_error_test() {
  let scope =
    scope.new()
    |> scope.newtype("Foo", [], [#("A", []), #("B", []), #("C", [])])

  let untyped =
    function(
      ["x"],
      case_(
        var("x"),
        [
          #(Destructure("A", []), binary()),
          #(Assignment("foo"), binary()),
          #(Assignment("bar"), binary()),
        ],
      ),
    )

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let RedundantClause("_") = failure
  let CaseClause = situation
}
