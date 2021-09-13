import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import eyg/ast
import eyg/ast/expression.{Binary, Call, Expression, Function, Let, Tuple}

pub type Path =
  List(Int)

pub type Horizontal {
  Left
  Right
}

pub type Action {
  WrapTuple
  Clear
  InsertSpace(Horizontal)
  Reorder(Horizontal)
}

pub type Edit {
  Edit(Action, Path)
}

pub fn edit(action, path) {
  Edit(action, path)
}

pub fn apply_edit(tree, edit) -> #(Expression(Nil), Path) {
  let Edit(action, path) = edit
  case action {
    WrapTuple -> wrap_tuple(tree, path)
    Clear -> clear(tree, path)
    InsertSpace(direction) -> {
      let Some(#(_tuple, tuple_path)) = parent_tuple(tree, path)
      let [cursor, .._] = list.drop(path, list.length(tuple_path))
      let cursor = case direction {
        Left -> cursor
        Right -> cursor + 1
      }
      let updated =
        map_node(
          tree,
          tuple_path,
          fn(node) {
            //   replace node to not need assert
            assert #(_, Tuple(elements)) = node
            let pre = list.take(elements, cursor)
            let post = list.drop(elements, cursor)
            let elements = list.flatten([pre, [ast.hole()], post])
            ast.tuple_(elements)
          },
        )
      #(updated, ast.append_path(tuple_path, cursor))
    }
    Reorder(direction) -> {
      let Some(#(#(_, Tuple(elements)), tuple_path)) = parent_tuple(tree, path)
    //   TODO fix cursor
      let [cursor, .._] = list.drop(path, list.length(tuple_path))
      let pre = list.take(elements, cursor)
      let [me, neighbour, ..post] = list.drop(elements, cursor)
      let updated = map_node(tree, tuple_path, fn(_) {
        ast.tuple_(list.append(pre, [neighbour, me, ..post]))
      }) 
      #(updated, ast.append_path(tuple_path, cursor))
    }
  }
}

fn wrap_tuple(tree: Expression(Nil), path: Path) {
  let updated = map_node(tree, path, fn(node) { ast.tuple_([node]) })
  #(updated, ast.append_path(path, 0))
}

fn clear(tree, path) {
  let updated = map_node(tree, path, fn(_) { ast.hole() })
  #(updated, path)
}

pub fn clear_action() -> Option(Action) {
  Some(Clear)
}

pub fn shotcut_for_binary(string, control_pressed) -> Option(Action) {
  case string, control_pressed {
    "[", True -> Some(WrapTuple)
    "Delete", True | "Backspace", True -> Some(Clear)
    "H", True -> Some(InsertSpace(Left))
    "L", True -> Some(InsertSpace(Right))
    "h", True -> Some(Reorder(Left))
    "l", True -> Some(Reorder(Right))
    _, _ -> None
  }
}

fn get_node(tree: Expression(Nil), path: List(Int)) -> Expression(Nil) {
  case tree, path {
    _, [] -> tree
    #(_, Let(pattern, value, then)), [0, ..rest] -> get_node(value, rest)
    #(_, Let(pattern, value, then)), [1, ..rest] -> get_node(then, rest)
    #(_, Tuple(elements)), [index, ..rest] -> {
      let [child, ..post] = list.drop(elements, index)
      get_node(child, rest)
    }
  }
}

fn parent_tuple(tree, path) {
  case get_node(tree, path) {
    #(_, Tuple(_)) -> Some(#(tree, path))
    _ ->
      case path {
        [] -> None
        _ -> parent_tuple(tree, list.take(path, list.length(path) - 1))
      }
  }
}

pub fn map_node(
  tree: Expression(Nil),
  path: List(Int),
  mapper: fn(Expression(Nil)) -> Expression(Nil),
) -> Expression(Nil) {
  let #(_, node) = tree
  case node, path {
    _, [] -> mapper(tree)
    Tuple(elements), [index, ..rest] -> {
      let pre = list.take(elements, index)
      let [current, ..post] = list.drop(elements, index)
      let updated = map_node(current, rest, mapper)
      let elements = list.flatten([pre, [updated], post])
      ast.tuple_(elements)
    }
    Let(pattern, value, then), [0, ..rest] ->
      ast.let_(pattern, map_node(value, rest, mapper), then)
    Let(pattern, value, then), [1, ..rest] ->
      ast.let_(pattern, value, map_node(then, rest, mapper))
  }
  //     [] -> replacement
  //     [index, ..rest] ->
  //       case tree {
  //         expression.Function(var, body) if index == 0 ->
  //           ast.function(var, replace_node(body, rest, replacement))
  //         expression.Name(type_, then) if index == 0 ->
  //           ast.name(type_, replace_node(then, rest, replacement))
  //         expression.Tuple(elements) -> {
  //           let inner = case replacement {
  //             #(_, expression.Provider(config: _config, generator: generator)) ->
  //               case ast.is_hole(generator) {
  //                 True -> []
  //                 False -> [replacement]
  //               }
  //             _ -> [replacement]
  //           }
  //         }
  //         expression.Row(fields) ->
  //           ast.row(index_map(
  //             fields,
  //             fn(i, field) {
  //               // i-1 compiler bug
  //               let i = i - 1
  //               case i == index {
  //                 True -> {
  //                   let #(name, exp) = field
  //                   #(name, replace_node(exp, rest, replacement))
  //                 }
  //                 False -> field
  //               }
  //             },
  //           ))
  //         expression.Call(func, with) if index == 0 ->
  //           ast.call(replace_node(func, rest, replacement), with)
  //         expression.Call(func, with) if index == 1 ->
  //           ast.call(func, replace_node(with, rest, replacement))
  //         expression.Case(type_, subject, clauses) if index == 0 ->
  //           ast.case_(type_, replace_node(subject, rest, replacement), clauses)
  //         expression.Case(type_, subject, clauses) if index > 0 -> {
  //           io.debug(index)
  //           let pre = list.take(clauses, index - 1)
  //           let [#(variant, variable, node), ..post] =
  //             list.drop(clauses, index - 1)
  //           let node = replace_node(node, rest, replacement)
  //           let clauses = list.append(pre, [#(variant, variable, node), ..post])
  //           ast.case_(type_, subject, clauses)
  //         }
  //         _ -> {
  //           io.debug(tree)
  //           io.debug(path)
  //           todo("not handled this node")
  //         }
  // }
}
// pub fn x(mapper: fn(List(Nil)) -> List(Nil)) -> Nil {
//   todo
// }
