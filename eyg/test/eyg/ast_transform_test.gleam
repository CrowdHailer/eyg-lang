import gleam/list
import gleam/io
import eyg/codegen/javascript
import eyg/ast
import eyg/ast/transform.{replace_node}
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer/polytype

fn hole() {
  ast.Provider(999, fn(x) { todo })
}

pub fn replace_node_test() {
  let original =
    ast.Function("$", ast.Let(pattern.Variable("x"), ast.Binary(""), hole()))
  let path = [0, 0]
  replace_node(original, path, ast.Binary("new"))

  let path = [0, 1]
  replace_node(original, path, ast.Binary("new"))

  let tuple =
    ast.Tuple([ast.Variable("x"), ast.Variable("y"), ast.Variable("z")])
  let path = [1]
  replace_node(tuple, path, ast.Binary("new"))
  |> io.debug()
}
// rename fn is replace node with new args
