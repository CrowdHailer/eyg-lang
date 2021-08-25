import gleam/io
import gleam/list
import eyg/ast
fn do_index_map(
  list: List(a),
  fun: fn(Int, a) -> b,
  index: Int,
  acc: List(b),
) -> List(b) {
  case list {
    [] -> list.reverse(acc)
    [x, ..xs] -> do_index_map(xs, fun, index + 1, [fun(index, x), ..acc])
  }
}

/// Returns a new list containing only the elements of the first list after the
/// function has been applied to each one and their index.
///
/// The index starts at 0, so the first element is 0, the second is 1, and so
/// on.
///
/// ## Examples
///
///    > index_map(["a", "b"], fn(i, x) { #(i, x) })
///    [#(0, "a"), #(1, "b")]
///
pub fn index_map(list: List(a), with fun: fn(Int, a) -> b) -> List(b) {
  do_index_map(list, fun, 0, [])
}

pub fn replace_node(
  tree: ast.Node,
  path: List(Int),
  replacement: ast.Node,
) -> ast.Node {
  case path {
    [] -> replacement
    [index, ..rest] ->
      case tree {
        ast.Function(var, body) if index == 0 ->
          ast.Function(var, replace_node(body, rest, replacement))
        ast.Let(pattern, value, then) if index == 0 ->
          ast.Let(pattern, replace_node(value, rest, replacement), then)
        ast.Let(pattern, value, then) if index == 1 ->
          ast.Let(pattern, value, replace_node(then, rest, replacement))
        // ast.Let(pattern, value, then) ->
        //   ast.Let(
        //     pattern,
        //     value,
        //     replace_node(then, [index - 1, ..rest], replacement),
        //   )
          //       ast.Name(type_, then) if index == 0 ->
          // ast.Name(pattern, replace_node(value, rest, replacement), then)
        ast.Name(type_, then) if index == 1 ->
          ast.Name(type_, replace_node(then, rest, replacement))
        ast.Name(type_, then) if index > 1 ->
          ast.Name(type_, replace_node(then, [index - 1, ..rest], replacement))
        ast.Tuple(elements) ->
          ast.Tuple(index_map(
            elements,
            fn(i, x) {
                let i = i - 1 
              case i == index {
                True -> replacement
                False -> x
              }
            },
          ))
        _ -> {
          io.debug(tree)
          io.debug(path)
          todo("not handled this node")
        }
      }
  }
}