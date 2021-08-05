import gleam/io
import gleam/list
import language/ast/builder.{
  binary, call, case_, destructure, function, let_, var,
}
import language/ast.{
  Assignment, Binary, Destructure, Let, ValueDestructuring, Var,
}
import language/type_.{CouldNotUnify, Data, Function, PolyType, Variable}
import language/scope
import language/ast/support

// Literals
pub fn infer_literal_binary_test() {
  let untyped = binary("abc")
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Data("Binary", []) = type_
}

// Custom record types. Does lambda calculus not go there, because functions are enough
// tuple vs rows only rows needed in spread sheets.
pub fn simple_custom_type_test() {
  let scope =
    scope.new()
    |> scope.newtype("Option", [1], [#("None", []), #("Some", [Variable(1)])])
    |> support.with_equal()
  let untyped = call(var("True"), [])
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Data("Boolean", []) = type_.resolve_type(type_, typer)

  let untyped =
    call(var("equal"), [call(var("None"), []), call(var("Some"), [binary("abc")])])
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Data("Boolean", []) = type_.resolve_type(type_, typer)
}

pub fn case_test() {
  let scope =
    scope.new()
    |> scope.newtype("Option", [1], [#("None", []), #("Some", [Variable(1)])])

  let untyped =
    case_(
      call(var("None"), []),
      [
        #(Destructure("Some", ["value"]), var("value")),
        #(Destructure("None", []), binary("abc")),
      ],
    )
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn distructure_incorrect_type_test() {
  let scope =
    scope.new()
    |> support.with_equal()
    |> scope.newtype("Option", [1], [#("None", []), #("Some", [Variable(1)])])

  let untyped =
    case_(
      call(var("True"), []),
      [
        #(Destructure("Some", ["value"]), var("value")),
        #(Destructure("None", []), binary("abc")),
      ],
    )
  let Error(#(failure, situation)) = ast.infer(untyped, scope)

  let CouldNotUnify(expected: Data("Boolean", []), given: Data("Option", [_])) =
    failure
  let ValueDestructuring("Some") = situation
}

pub fn clause_return_missmatch_test() {
  let scope =
    scope.new()
    |> support.with_equal()
    |> scope.newtype("Option", [1], [#("None", []), #("Some", [Variable(1)])])

  let untyped =
    case_(
      call(var("True"), []),
      [
        #(Destructure("True", []), call(var("False"), [])),
        #(Destructure("False", []), binary("abc")),
      ],
    )
  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let CouldNotUnify(expected: Data("Boolean", []), given: Data("Binary", [])) =
    failure
}

pub fn mismatched_pattern_test() {
  let scope =
    scope.new()
    |> support.with_equal()
    |> scope.newtype("Option", [1], [#("None", []), #("Some", [Variable(1)])])

  let untyped =
    function(
      ["x"],
      case_(
        var("x"),
        [
          #(Destructure("True", []), binary("abc")),
          #(Destructure("None", []), binary("abc")),
        ],
      ),
    )
  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let CouldNotUnify(expected: Data("Boolean", []), given: Data("Option", [_])) =
    failure
}

pub fn unify_types_in_fn_args_test() {
  let scope =
    scope.new()
    |> support.with_equal()

  let untyped = function(["x", "y"], call(var("equal"), [var("x"), var("y")]))
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Function([t, u], Data("Boolean", [])) = type_.resolve_type(type_, typer)
  let True = t == u
}

pub fn case_with_function_test() {
  let scope =
    scope.new()
    |> scope.newtype("Option", [1], [#("None", []), #("Some", [Variable(1)])])

  let untyped =
    function(
      ["x"],
      case_(
        var("x"),
        [
          #(Destructure("Some", ["value"]), var("value")),
          #(Destructure("None", []), binary("abc")),
        ],
      ),
    )
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Function([Data("Option", [Data("Binary", [])])], Data("Binary", [])) =
    type_.resolve_type(type_, typer)
}
