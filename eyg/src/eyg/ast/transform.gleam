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
  tree: ast.Expression(a),
  path: List(Int),
  replacement: ast.Expression(a),
) -> ast.Expression(a) {
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
        ast.Let(pattern, value, then) ->
          ast.Let(
            pattern,
            value,
            replace_node(then, [index - 1, ..rest], replacement),
          )
        ast.Name(type_, then) if index == 0 && rest == [] -> replacement
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
        ast.Call(func, with) if index == 0 ->
          ast.Call(replace_node(func, rest, replacement), with)
        ast.Case(type_, subject, clauses) if index == 0 ->  

          ast.Case(type_, replace_node(subject, rest, replacement), clauses)
        ast.Case(type_, subject, clauses) if index > 0 ->  {
          io.debug(index)
          let pre = list.take(clauses, index - 1)
          let [#(variant, variable, node), ..post] = list.drop(clauses, index - 1)
          let node = replace_node(node, rest, replacement)
          let clauses = list.append(pre, [#(variant, variable, node), ..post])
          ast.Case(type_, subject, clauses)
        }
        _ -> {
          io.debug(tree)
          io.debug(path)
          todo("not handled this node")
        }
      }
  }
}

pub fn change_type_name(type_, new_name) {
  let #(type_name, #(params, variants)) = type_
  #(new_name, #(params, variants))
}

pub fn change_variant(type_, index, new_name) {
  let #(type_name, #(params, variants)) = type_
  let pre = list.take(variants, index)
  let [variant, ..post] = list.drop(variants, index)
  let #(_name, arguments) = variant
  let variant = #(new_name, arguments)
  let variants = list.append(pre, [variant, ..post])
  #(type_name, #(params, variants))
}

pub fn add_variant(type_, after, new_name) {
  let #(type_name, #(params, variants)) = type_
  let pre = list.take(variants, after + 1)
  let post = list.drop(variants, after + 1)
  let variant = #("_", ast.Tuple([]))
  let variants = list.append(pre, [variant, ..post])
  #(type_name, #(params, variants))
}
