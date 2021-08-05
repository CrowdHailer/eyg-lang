import language/codegen/javascript
import language/ast/builder.{
  binary, call, case_, destructure, function, let_, var,
}
import language/type_.{Data}
import language/ast
import language/scope
import language/ast/support.{with_equal}

fn compile(untyped, scope) {
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  javascript.render(#(type_, tree))
}

pub fn variable_assignment_test() {
  let untyped =
    let_("foo", binary("My First Value"), let_("foo", var("foo"), var("foo")))
  let js = compile(untyped, scope.new())
  let [l1, l2, l3] = js
  let "let foo$1 = \"My First Value\";" = l1
  let "let foo$2 = foo$1;" = l2
  let "foo$2" = l3
}

// TODO how are functions parsed around
// pub fn let_destructure_test() {
//   let scope =
//     scope.new()
//     |> scope.newtype("User", [], [#("User", [Data("Binary", [])])])

//   let untyped =
//     destructure(
//       "User",
//       ["first_name"],
//       call(var("User"), [binary("abc")]),
//       var("first_name"),
//     )
//   let js = compile(untyped, scope)
//   let [l1, l2] = js
//   let "let foo$1 = \"My First Value\";" = l1
//   let "let foo$2 = foo$1;" = l2
// }
// 
// TODO test multiline in let value


pub fn simple_function_call_test() {
  let scope
  = scope.new()
  |> with_equal
  let untyped =
    call(var("equal"), [binary("foo"), binary("bar")])
  let js = compile(untyped, scope)
  let [l1] = js
  let "equal$1(\"foo\", \"bar\", )" = l1
}

pub fn oneline_function_test() {
    let scope
  = scope.new()
  let untyped =
  let_("x", function(["x"], var("x")), var("x"))
    let js = compile(untyped, scope)
  let [l1] = js
  let "equal$1(\"foo\", \"bar\", )" = l1
}