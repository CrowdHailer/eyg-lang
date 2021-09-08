import gleam/list
import gleam/io
import eyg/codegen/javascript
import eyg/ast
import eyg/ast/transform.{replace_node}
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer/polytype

fn hole() {
  ast.provider(999, fn(x) { todo })
}

pub fn replace_node_test() {
  let original =
    ast.function("$", ast.let_(pattern.Variable("x"), ast.binary(""), hole()))
  let path = [0, 0]
  replace_node(original, path, ast.binary("new"))

  let path = [0, 1]
  replace_node(original, path, ast.binary("new"))

  let tuple =
    ast.tuple_([ast.variable("x"), ast.variable("y"), ast.variable("z")])
  let path = [1]
  replace_node(tuple, path, ast.binary("new"))
  |> io.debug()
}
// rename fn is replace node with new args
