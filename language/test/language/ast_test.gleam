import gleam/io
import gleam/list
import language/ast/builder.{
  binary, call, case_, destructure, function, let_, var,
}
import language/ast.{Assignment, Binary, Destructure, Let, Var}
import language/type_.{Data, Function, PolyType, Variable}
import language/scope

// Literals
pub fn infer_literal_binary_test() {
  let untyped = binary()
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Data("Binary", []) = type_
}

// assignments
pub fn infer_type_constructor_for_var_test() {
  let untyped = let_("foo", binary(), var("foo"))
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Data("Binary", []) = type_
  let Let(
    Assignment("foo"),
    #(Data("Binary", []), Binary),
    #(Data("Binary", []), Var("foo")),
  ) = tree
}

pub fn compile_error_for_missing_var_test() {
  let untyped = let_("foo", binary(), var("bar"))
  let Error(_) = ast.infer(untyped, scope.new())
}

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
  let Data("Binary", []) = type_.resolve_type(type_, typer)
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

  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope.new())
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

// Custom record types. Does lambda calculus not go there, because functions are enough
// tuple vs rows only rows needed in spread sheets.
pub fn simple_custom_type_test() {
  let scope =
    scope.new()
    |> scope.newtype("Boolean", [], [#("True", []), #("False", [])])
    |> scope.newtype("Option", [1], [#("None", []), #("Some", [Variable(1)])])
    |> with_equal()
  let untyped = call(var("True"), [])
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Data("Boolean", []) = type_.resolve_type(type_, typer)

  let untyped =
    call(var("equal"), [call(var("None"), []), call(var("Some"), [binary()])])
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Data("Boolean", []) = type_.resolve_type(type_, typer)
}

fn with_equal(scope) {
  scope
  |> scope.newtype("Boolean", [], [#("True", []), #("False", [])])
  |> scope.set_variable(
    "equal",
    PolyType([1], Function([Variable(1), Variable(1)], Data("Boolean", []))),
  )
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

pub fn unify_types_in_fn_args_test() {
  let scope =
    scope.new()
    |> with_equal()

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

pub fn generalising_restricted_by_scope_test() {
  let scope =
    scope.new()
    |> with_equal()
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

pub fn call_error_messages_test() {
  let scope =
    scope.new()
    |> with_equal()

  // let too_many_args = call(var("equal"), [binary(), binary(), binary()])
  // let Error("too many args to unify")= ast.infer(too_many_args, scope)

  // let too_many_args = call(var("equal"), [binary()])
  // let Error("too few args to unify")= ast.infer(too_many_args, scope)
  
  

  let too_many_args = call(var("equal"), [binary(), call(var("True"), [])])
  let Ok(_)= ast.infer(too_many_args, scope)

  io.debug(#("hell", 1))
  let 1 = 0
}