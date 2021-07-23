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
  io.debug(tree)
  io.debug(substitutions)
  let Variable(1) = type_
  // This is the resolving of the variable
  // lookup needs to be recursive
  let Ok(Constructor("Binary", [])) = list.key_find(substitutions, 1)
}
// pub fn infer_call_with_arguments_test() {
//   let ast = #(
//     Nil,
//     Call(#(Nil, Function([#(Nil, "x")], #(Nil, Var("x")))), [#(Nil, Binary)]),
//   )
//   let Ok(#(Constructor("Binary", []), _, _)) = infer(ast, initial)
// }
