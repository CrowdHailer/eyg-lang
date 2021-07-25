import gleam/io
import gleam/list
import language/ast.{binary, call, function, let_, var}
import language/ast.{Binary, Constructor, Let, Var, Variable}

// Literals
pub fn infer_literal_binary_test() {
  let untyped = binary()
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped)
  // seems not to be ok as assert
  let Constructor("Binary", []) = type_
}

// assignments
pub fn infer_type_constructor_for_var_test() {
  let untyped = let_("foo", binary(), var("foo"))
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped)
  // seems not to be ok as assert
  let Constructor("Binary", []) = type_
  let Let(
    "foo",
    #(Constructor("Binary", []), Binary),
    #(Constructor("Binary", []), Var("foo")),
  ) = tree
}

pub fn compile_error_for_missing_var_test() {
  let untyped = let_("foo", binary(), var("bar"))
  let Error(_) = ast.infer(untyped)
}

pub fn infer_identity_function_test() {
  let untyped = function([#(Nil, "x")], var("x"))
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped)
  let Constructor("Function", [Variable(1), Variable(1)]) = type_
}

pub fn infer_call_test() {
  let untyped = call(function([], binary()), [])
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped)
  let Constructor("Binary", []) = ast.resolve_type(type_, substitutions)
}

pub fn infer_call_with_arguments_test() {
  let untyped = call(function([#(Nil, "x")], var("x")), [binary()])
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped)
  let Constructor("Binary", []) = ast.resolve_type(type_, substitutions)
}

// infer with wrong call arguments
pub fn generic_functions_test() {
  let identity = function([#(Nil, "x")], var("x"))
  let untyped =
    let_(
      "id",
      identity,
      let_("temp", call(var("id"), [var("id")]), call(var("temp"), [binary()])),
    )
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped)
  let Constructor("Binary", []) = ast.resolve_type(type_, substitutions)
}

// Custom record types. Does lambda calculus not go there, because functions are enough
// tuple vs rows only rows needed in spread sheets.
// Constructor("Foo")
// Bool{
//   True
//   False
// }
// "Some" = PolyType(
//   forall: [1], 
//   Constructor("Function", [Variable(1), Constructor("Option", [Variable(1)])]))
pub fn simple_custom_type_test() {
  // let untyped = newtype(
  //   "Boolean", 
  //   [constructor("True", []), constructor("False", [])],
  //   call(var("True"), [])
  // )
  let untyped = call(var("True"), [])
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped)
  let Constructor("Boolean", []) = ast.resolve_type(type_, substitutions)

  // let untyped = call(var("None"), [])
  // let Ok(#(type_, tree, substitutions)) = ast.infer(untyped)
  // let Constructor("Option", [_]) = ast.resolve_type(type_, substitutions)

  let untyped = call(var("equal"), [call(var("None"), []), call(var("Some"), [binary()])])
  let Ok(#(type_, tree, substitutions)) = ast.infer(untyped)
  |> io.debug()
  let Constructor("Boolean", []) = ast.resolve_type(type_, substitutions)

}
