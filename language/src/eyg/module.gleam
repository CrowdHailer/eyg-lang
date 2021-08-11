import gleam/io
import gleam/list
import gleam/string
import language/type_.{PolyType, Function, Variable, Data}
import language/codegen/javascript
import language/ast
import language/scope
import language/ast/builder.{
  binary, call, case_, constructor, function, let_, row, var, varient,
}

fn module() {
  let_(
    "tmp",
    binary("temp"),
    row([#("hello_world_test", function([], call(var("should.equal"), [binary("Hello, World!"), binary("goo")])))]),
  )
}

pub fn compiled() {
    assert #(scope, #("should.equal", 1)) =
    scope.new()
    |> scope.set_variable(
      "should.equal",
      PolyType([1], Function([Variable(1), Variable(1)], Data("Boolean", []))),
    )
  case ast.infer(module(), scope) {
    Ok(#(type_, tree, substitutions)) -> {
        javascript.maybe_wrap_expression(#(type_, tree))
        |> list.intersperse("\n")
        |> string.concat()
    }
    Error(info) -> {
        io.debug(ast.failure_to_string(info))
        todo("FAILED TO COMPILE")
    }
  }
}
