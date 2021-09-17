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

// t -> wrap tuple
// u -> unwrap
// d -> delete
pub fn handle_keydown(tree, position, key) {
  case key {
    "a" -> {
      let path = case parent_path(position) {
        Some(#(p, _)) -> p
        None -> []
      }
      #(tree, path)
    }
    "s" -> #(tree, ast.append_path(position, 0))
    "h" -> {
      let [index, ..rest] = list.reverse(position)
      #(tree, list.reverse([index - 1, ..rest]))
    }
    "l" -> {
      let [index, ..rest] = list.reverse(position)
      #(tree, list.reverse([index + 1, ..rest]))
    }
    "t" -> wrap_tuple(tree, position)
    "u" -> unwrap(tree, position)
    "d" -> delete(tree, position)
    _ -> {
      1
      todo("doesn't do anything")
    }
  }
}

fn wrap_tuple(tree, position) {
  let target = get_element(tree, position)
  // TODO don't wrap multi line terms
  let modified = case target {
    Expression(expression) ->
      replace_node(tree, position, ast.tuple_([expression]))
    Pattern(p.Variable(label)) -> {
      assert Some(#(path, _)) = parent_path(position)
      assert Expression(#(_, e.Let(_, value, then))) = get_element(tree, path)
      let new = ast.let_(p.Tuple([label]), value, then)
      replace_node(tree, path, new)
    }
  }
  #(modified, ast.append_path(position, 0))
}

fn unwrap(tree, position) {
  case parent_path(position) {
    None -> #(tree, position)
    Some(#(position, index)) -> {
      let parent = get_element(tree, position)
      case parent {
        Expression(#(_, e.Tuple(elements))) -> {
          let [replacement, .._] = list.drop(elements, index)
          let modified = replace_node(tree, position, replacement)
          #(modified, position)
        }
        Expression(_) -> unwrap(tree, position)
        Pattern(p.Tuple(elements)) -> {
          let [label, .._] = list.drop(elements, index)
          assert Some(#(position, _)) = parent_path(position)
          assert Expression(#(_, e.Let(_, value, then))) =
            get_element(tree, position)
          let new = ast.let_(p.Variable(label), value, then)
          let modified = replace_node(tree, position, new)
          #(modified, list.append(position, [0]))
        }
      }
    }
  }
}

fn delete(tree, position) {
  let replacement = case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, then))) -> then
    Expression(_) -> ast.hole()
  }
  let modified = replace_node(tree, position, replacement)
  #(modified, position)
}

fn parent_path(path) {
  case list.reverse(path) {
    [] -> None
    [last, ..rest] -> Some(#(list.reverse(rest), last))
  }
}

pub fn get_element(tree, position) {
  case tree, position {
    _, [] -> Expression(tree)
    #(_, e.Tuple(elements)), [i, ..rest] -> {
      let [child, .._] = list.drop(elements, i)
      get_element(child, rest)
    }
    #(_, e.Let(pattern, _, _)), [0] -> Pattern(pattern)
    #(_, e.Let(p.Tuple(elements), _, _)), [0, i] -> {
      let [element, .._] = list.drop(elements, i)
      PatternElement(i, element)
    }
    #(_, e.Let(_, value, _)), [1, ..rest] -> get_element(value, rest)
    #(_, e.Let(_, _, then)), [2, ..rest] -> get_element(then, rest)
    #(_, e.Function(pattern, _)), [0] -> Pattern(pattern)
    #(_, e.Function(_, body)), [1, ..rest] -> get_element(body, rest)
    #(_, e.Call(func, _)), [0, ..rest] -> get_element(func, rest)
    #(_, e.Call(_, with)), [1, ..rest] -> get_element(with, rest)
    _, _ -> {
      io.debug(tree)
      io.debug(position)
      todo("unhandled get_element")
    }
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
  io.debug(node)
  case node, path {
    _, [] -> mapper(tree)
    e.Tuple(elements), [index, ..rest] -> {
      let pre = list.take(elements, index)
      let [current, ..post] = list.drop(elements, index)
      let updated = map_node(current, rest, mapper)
      let elements = list.flatten([pre, [updated], post])
      ast.tuple_(elements)
    }
    e.Let(pattern, value, then), [1, ..rest] ->
      ast.let_(pattern, map_node(value, rest, mapper), then)
    e.Let(pattern, value, then), [2, ..rest] ->
      ast.let_(pattern, value, map_node(then, rest, mapper))
    e.Function(pattern, body), [1, ..rest] ->
      ast.function(pattern, map_node(body, rest, mapper))
    e.Call(func, with), [0, ..rest] ->
      ast.call(map_node(func, rest, mapper), with)
    e.Call(func, with), [1, ..rest] ->
      ast.call(func, map_node(with, rest, mapper))

    _, _ -> {
      io.debug(node)
      io.debug(path)
      todo("unhandled node map")
    }
  }
}
