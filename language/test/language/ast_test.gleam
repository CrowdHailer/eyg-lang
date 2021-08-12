import gleam/io
import gleam/list
import language/ast/builder.{
  binary, call, case_, constructor, function, var, varient,
}
import language/ast.{Destructure, ValueDestructuring}
import language/type_.{CouldNotUnify, Data, Function, Variable}
import language/scope
import language/ast/support

// Literals
pub fn infer_literal_binary_test() {
  let untyped = binary("abc")
  let Ok(#(type_, _tree, _typer)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Data("Binary", []) = type_
}

// Custom record types. Does lambda calculus not go there, because functions are enough
// tuple vs rows only rows needed in spread sheets.
pub fn simple_custom_type_test() {
  let scope =
    scope.new()
    |> scope.with_equal()

  let untyped =
    varient(
      "option::Option",
      [1],
      [constructor("Some", [Variable(1)]), constructor("None", [])],
      call(
        var("equal"),
        [call(var("None"), []), call(var("Some"), [binary("abc")])],
      ),
    )
  let Ok(#(type_, _tree, typer)) = ast.infer(untyped, scope)
  let Data("Boolean", []) = type_.resolve_type(type_, typer)
}

pub fn case_test() {
  let scope = scope.new()

  let untyped =
    support.with_option(case_(
      call(var("None"), []),
      [
        #(Destructure("Some", ["value"]), var("value")),
        #(Destructure("None", []), binary("abc")),
      ],
    ))

  let Ok(#(type_, _tree, typer)) = ast.infer(untyped, scope)
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn distructure_incorrect_type_test() {
  let scope =
    scope.new()
    |> scope.with_equal()

  let untyped =
    support.with_boolean(support.with_option(case_(
      call(var("True"), []),
      [
        #(Destructure("Some", ["value"]), var("value")),
        #(Destructure("None", []), binary("abc")),
      ],
    )))

  let Error(#(failure, situation)) = ast.infer(untyped, scope)

  let CouldNotUnify(expected: Data("Boolean", []), given: Data("Option", [_])) =
    failure
  let ValueDestructuring("Some") = situation
}

pub fn clause_return_missmatch_test() {
  let scope =
    scope.new()
    |> scope.with_equal()

  let untyped =
    support.with_boolean(case_(
      call(var("True"), []),
      [
        #(Destructure("True", []), call(var("False"), [])),
        #(Destructure("False", []), binary("abc")),
      ],
    ))
  let Error(#(failure, _situation)) = ast.infer(untyped, scope)
  let CouldNotUnify(expected: Data("Boolean", []), given: Data("Binary", [])) =
    failure
}

pub fn mismatched_pattern_test() {
  let scope =
    scope.new()
    |> scope.with_equal()

  let untyped =
    support.with_boolean(support.with_option(function(
      ["x"],
      case_(
        var("x"),
        [
          #(Destructure("True", []), binary("abc")),
          #(Destructure("None", []), binary("abc")),
        ],
      ),
    )))
  let Error(#(failure, _situation)) = ast.infer(untyped, scope)
  let CouldNotUnify(expected: Data("Boolean", []), given: Data("Option", [_])) =
    failure
}

pub fn unify_types_in_fn_args_test() {
  let scope =
    scope.new()
    |> scope.with_equal()

  let untyped = function(["x", "y"], call(var("equal"), [var("x"), var("y")]))
  let Ok(#(type_, _tree, typer)) = ast.infer(untyped, scope)
  let Function([t, u], Data("Boolean", [])) = type_.resolve_type(type_, typer)
  let True = t == u
}

pub fn case_with_function_test() {
  let scope = scope.new()

  let untyped =
    support.with_option(function(
      ["x"],
      case_(
        var("x"),
        [
          #(Destructure("Some", ["value"]), var("value")),
          #(Destructure("None", []), binary("abc")),
        ],
      ),
    ))
  let Ok(#(type_, _tree, typer)) = ast.infer(untyped, scope)
  let Function([Data("Option", [Data("Binary", [])])], Data("Binary", [])) =
    type_.resolve_type(type_, typer)
}
