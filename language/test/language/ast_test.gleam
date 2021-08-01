import gleam/io
import gleam/list
import language/ast/builder.{
  binary, call, case_, destructure, function, let_, var,
}
import language/ast.{Assignment, Binary, Destructure, Let, Var}
import language/type_.{Data, Function, PolyType, Variable, CouldNotUnify}
import language/scope
import language/ast/support

// Literals
pub fn infer_literal_binary_test() {
  let untyped = binary()
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
    call(var("equal"), [call(var("None"), []), call(var("Some"), [binary()])])
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
        #(Destructure("None", []), binary()),
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
        #(Destructure("None", []), binary()),
      ],
    )
  let Error(CouldNotUnify(expected: Data("Boolean", []), given: Data("Option", [_]))) = ast.infer(untyped, scope)
}

pub fn clause_missmatch_test() {
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
          #(Destructure("Some", ["value"]), var("value")),
          #(Destructure("True", []), binary()),
        ],
      ),
    )
    // TODO need to rewrite through this as expected
  let Error(CouldNotUnify(expected: Data("Option", [_]), given: Data("Boolean", []))) = ast.infer(untyped, scope)
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
          #(Destructure("None", []), binary()),
        ],
      ),
    )
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Function([Data("Option", [Data("Binary", [])])], Data("Binary", [])) =
    type_.resolve_type(type_, typer)
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
          #(Destructure("None", []), binary()),
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
      call(var("make_match"), [binary()]),
    )

  // make match is a fn type that should Not be generalised
  // isolated let etc can there be a whole that get's the scope
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Function([Data("Binary", [])], Data("Boolean", [])) =
    type_.resolve_type(type_, typer)
}
