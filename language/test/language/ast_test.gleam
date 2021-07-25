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
