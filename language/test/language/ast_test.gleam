import gleam/io
import gleam/list
import language/ast.{binary, call, case_, destructure, function, let_, var}
import language/ast.{Binary, Destructure, Let, Name, Var}
import language/type_.{Constructor, PolyType, Variable}
import language/scope

// Literals
pub fn infer_literal_binary_test() {
  let untyped = binary()
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Constructor("Binary", []) = type_
}

// assignments
pub fn infer_type_constructor_for_var_test() {
  let untyped = let_("foo", binary(), var("foo"))
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Constructor("Binary", []) = type_
  let Let(
    Name("foo"),
    #(Constructor("Binary", []), Binary),
    #(Constructor("Binary", []), Var("foo")),
  ) = tree
}

pub fn compile_error_for_missing_var_test() {
  let untyped = let_("foo", binary(), var("bar"))
  let Error(_) = ast.infer(untyped, scope.new())
}

pub fn infer_identity_function_test() {
  let untyped = function(["x"], var("x"))
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope.new())
  let Constructor("Function", [Variable(a), Variable(b)]) = type_
  let True = a == b
}

pub fn infer_call_test() {
  let untyped = call(function([], binary()), [])
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope.new())
  let Constructor("Binary", []) = type_.resolve_type(type_, substitutions)
}

pub fn infer_call_with_arguments_test() {
  let untyped = call(function(["x"], var("x")), [binary()])
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope.new())
  let Constructor("Binary", []) = type_.resolve_type(type_, substitutions)
}

// infer with wrong call arguments
pub fn generic_functions_test() {
  let identity = function(["x"], var("x"))
  let untyped =
    let_(
      "id",
      identity,
      let_("temp", call(var("id"), [var("id")]), call(var("temp"), [binary()])),
    )
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope.new())
  let Constructor("Binary", []) = type_.resolve_type(type_, substitutions)
}

// Custom record types. Does lambda calculus not go there, because functions are enough
// tuple vs rows only rows needed in spread sheets.
pub fn simple_custom_type_test() {
  let scope =
    scope.new()
    |> scope.newtype("Boolean", [], [#("True", []), #("False", [])])
    |> scope.newtype("Option", [1], [#("None", []), #("Some", [Variable(1)])])
    |> scope.set_variable(
      "equal",
      PolyType(
        [1],
        Constructor(
          "Function",
          [Variable(1), Variable(1), Constructor("Boolean", [])],
        ),
      ),
    )

  let untyped = call(var("True"), [])
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope)
  let Constructor("Boolean", []) = type_.resolve_type(type_, substitutions)

  let untyped =
    call(var("equal"), [call(var("None"), []), call(var("Some"), [binary()])])
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope)
  let Constructor("Boolean", []) = type_.resolve_type(type_, substitutions)
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
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope)
  let Constructor("Binary", []) = type_.resolve_type(type_, substitutions)
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
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope)
  let Constructor(
    "Function",
    [
      Constructor("Option", [Constructor("Binary", [])]),
      Constructor("Binary", []),
    ],
  ) = type_.resolve_type(type_, substitutions)
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
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope)
  let Constructor("Function", [input, return]) =
    type_.resolve_type(type_, substitutions)
}

pub fn destructure_test() {
  let scope =
    scope.new()
    |> scope.newtype("User", [], [#("User", [Constructor("Binary", [])])])

  let untyped =
    destructure(
      "User",
      ["first_name"],
      call(var("User"), [binary()]),
      var("first_name"),
    )
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped, scope)
  let Constructor("Binary", []) = type_.resolve_type(type_, substitutions)
}
