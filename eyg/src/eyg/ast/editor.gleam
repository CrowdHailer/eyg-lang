import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p

pub type Element {
  Expression(e.Expression(Nil))
  Pattern(p.Pattern)
  PatternElement(Int, String)
}

pub fn get_element(tree, position) {
  io.debug(tree)
  case tree, position {
    _, [] -> Expression(tree)
    #(_, e.Let(pattern, _, _)), [0] -> Pattern(pattern)
    #(_, e.Let(p.Tuple(elements), _, _)), [0, i] -> {
      let [element, .._] = list.drop(elements, i)
      PatternElement(i, element)
    }
    #(_, e.Let(_, value, _)), [1, ..rest] -> get_element(value, rest)
    #(_, e.Let(_, _, then)), [2, ..rest] -> get_element(then, rest)
    #(_, e.Function(pattern, _)), [0] -> Pattern(pattern)
    #(_, e.Call(func, _)), [0, ..rest] -> get_element(func, rest)
    #(_, e.Call(_, with)), [1, ..rest] -> get_element(with, rest)
  }
}

pub fn handle_keydown(tree, position, key) {
  let target = get_element(tree, position)
  case target, key {
    _, "a" -> {
      let path = case parent_path(position) {
        Some(#(p, _)) -> p
        None -> []
      }
      #(tree, path)
    }
    _, "s" -> #(tree, ast.append_path(position, 0))
    _, "h" -> {
      let [index, ..rest] = list.reverse(position)
      #(tree, list.reverse([index - 1, ..rest]))
    }
    _, "l" -> {
      let [index, ..rest] = list.reverse(position)
      #(tree, list.reverse([index + 1, ..rest]))
    }
    Pattern(p.Variable(label)), "[" -> {
      let Some(#(path, _)) = parent_path(position)
      let Expression(#(_, e.Let(_, value, then))) = get_element(tree, path)
      let new = ast.let_(p.Tuple([label]), value, then)
      let modified = replace_node(tree, path, new)
      #(modified, list.append(path, [0, 0]))
    }
    PatternElement(_, label), "u" -> {
      let Some(#(path, _)) = parent_path(position)
      let Some(#(path, _)) = parent_path(path)
      let Expression(#(_, e.Let(_, value, then))) = get_element(tree, path)
      let new = ast.let_(p.Variable(label), value, then)
      let modified = replace_node(tree, path, new)
      #(modified, list.append(path, [0]))
    }
    _, _ -> {
      1
      todo("doesn't do anything")
    }
  }
}

fn parent_path(path) {
  case list.reverse(path) {
    [] -> None
    [last, ..rest] -> Some(#(list.reverse(rest), last))
  }
}

pub fn replace_node(
  tree: e.Expression(Nil),
  path: List(Int),
  replacement: e.Expression(Nil),
) -> e.Expression(Nil) {
  map_node(tree, path, fn(_) { replacement })
}

pub fn map_node(
  tree: e.Expression(Nil),
  path: List(Int),
  mapper: fn(e.Expression(Nil)) -> e.Expression(Nil),
) -> e.Expression(Nil) {
  let #(_, node) = tree
  case node, path {
    _, [] -> mapper(tree)
  }
  // Tuple(elements), [index, ..rest] -> {
  //   let pre = list.take(elements, index)
  //   let [current, ..post] = list.drop(elements, index)
  //   let updated = map_node(current, rest, mapper)
  //   let elements = list.flatten([pre, [updated], post])
  //   ast.tuple_(elements)
  // }
  // Let(pattern, value, then), [0, ..rest] ->
  //   ast.let_(pattern, map_node(value, rest, mapper), then)
  // Let(pattern, value, then), [1, ..rest] ->
  //   ast.let_(pattern, value, map_node(then, rest, mapper))
  // Function(var, body), [0, ..rest] ->
  //   ast.function(var, map_node(body, rest, mapper))
}
