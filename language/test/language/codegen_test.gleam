import language/codegen/javascript
import language/ast/builder.{
  binary, call, case_, destructure, function, let_, var,
}
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
}
