import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import eyg/ast
import eyg/ast/pattern
import standard/builders
import eyg/ast/expression.{Binary, Call, Expression, Function, Let, Tuple}

pub type Path =
  List(Int)

pub type Horizontal {
  Left
  Right
}

pub type Vertical {
  Above
  Below
}

pub type Action {
  SelectParent
  WrapTuple
  WrapAssignment
  WrapFunction
  Unwrap
  Clear
  InsertSpace(Horizontal)
  InsertLine(Vertical)
  //   Reorder = Drag horizontal
  Reorder(Horizontal)
  DragLine(Vertical)
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
    SelectParent -> {
      let path = case parent_path(path) {
        Some(#(path, index)) -> path
        None -> path
      }
      #(tree, path)
    }
    WrapTuple -> wrap_tuple(tree, path)
    WrapAssignment -> wrap_assignment(tree, path)
    WrapFunction -> wrap_function(tree, path)
    Unwrap -> unwrap(tree, path)
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
      let [cursor, ..rest] = list.drop(path, list.length(tuple_path))
      let #(cursor, after) = case direction {
        Left -> #(cursor - 1, cursor - 1)
        Right -> #(cursor, cursor + 1)
      }
      let l = list.length(elements) - 2
      case cursor {
        c if c >= 0 && c <= l -> {
          let pre = list.take(elements, cursor)
          let [me, neighbour, ..post] = list.drop(elements, cursor)
          let updated =
            map_node(
              tree,
              tuple_path,
              fn(_) { ast.tuple_(list.append(pre, [neighbour, me, ..post])) },
            )
          #(updated, ast.append_path(tuple_path, after))
        }
        _ -> #(tree, tuple_path)
      }
    }
    InsertLine(direction) ->
      case direction {
        Above -> insert_line_above(tree, path, 0)
      }
  }
  // TODO insert Below
}

fn parent_path(path) {
  case list.reverse(path) {
    [] -> None
    [last, ..rest] -> Some(#(list.reverse(rest), last))
  }
}

fn wrap_tuple(tree: Expression(Nil), path: Path) {
  let updated = map_node(tree, path, fn(node) { ast.tuple_([node]) })
  #(updated, ast.append_path(path, 0))
}

fn wrap_assignment(tree: Expression(Nil), path: Path) {
  let updated = case parent_path(path) {
    None -> ast.let_(pattern.Variable(""), tree, ast.hole())
    Some(#(parent_path, index)) ->
      case get_node(tree, parent_path) {
        #(_, Let(_, _, _)) -> tree
        _ ->
          map_node(
            tree,
            path,
            fn(node) { ast.let_(pattern.Variable(""), node, ast.hole()) },
          )
      }
  }
  #(updated, path)
}

fn wrap_function(tree: Expression(Nil), path: Path) {
  let updated = map_node(tree, path, fn(node) { builders.function([], node) })
  // Nested append because of the tuple in the the built ast
  let new_path = ast.append_path(ast.append_path(path, 0), 1)
  #(updated, new_path)
}

fn unwrap(tree: Expression(Nil), path: Path) {
  let expression = get_node(tree, path)
  case parent_path(path) {
    None -> #(tree, [])
    Some(#(path, _index)) -> {
      let updated = map_node(tree, path, fn(_) { expression })
      #(updated, path)
    }
  }
}

fn clear(tree, path) {
  let updated = map_node(tree, path, fn(_) { ast.hole() })
  #(updated, path)
}

fn insert_line_above(tree, path, last_index) {
  let target = get_node(tree, path)
  case target {
    #(_, Let(pattern, value, then)) ->
      case last_index {
        0 -> {
          let updated = ast.let_(pattern.Variable(""), ast.hole(), tree)
          #(updated, path)
        }
        1 -> {
          let updated =
            ast.let_(
              pattern,
              value,
              ast.let_(pattern.Variable(""), ast.hole(), then),
            )
          #(updated, ast.append_path(path, 1))
        }
      }
    _ ->
      case parent_path(path) {
        None -> #(ast.let_(pattern.Variable(""), ast.hole(), tree), [])
        Some(#(path, index)) -> insert_line_above(tree, path, index)
      }
  }
}

pub fn clear_action() -> Option(Action) {
  Some(Clear)
}

pub fn shotcut_for_binary(string, control_pressed) -> Option(Action) {
  case string, control_pressed {
    // maybe a is select all and s for select but ctrl s is definetly save
    "a", True -> Some(SelectParent)
    "[", True -> Some(WrapTuple)
    "=", True -> Some(WrapAssignment)
    ">", True -> Some(WrapFunction)
    "u", True -> Some(Unwrap)
    "Delete", True | "Backspace", True -> Some(Clear)
    "H", True -> Some(InsertSpace(Left))
    "L", True -> Some(InsertSpace(Right))
    "J", True -> Some(InsertLine(Above))
    "K", True -> Some(InsertLine(Below))
    "h", True -> Some(Reorder(Left))
    "l", True -> Some(Reorder(Right))
    _, _ -> None
  }
}

pub fn shotcut_for_tuple(string, control_pressed) -> Option(Action) {
  case string, control_pressed {
    // maybe a is select all and s for select but ctrl s is definetly save
    "a", _ -> Some(SelectParent)
    // "[", True -> Some(WrapTuple)
    // "=", True -> Some(WrapAssignment)
    // "u", True -> Some(Unwrap)
    // "Delete", True | "Backspace", True -> Some(Clear)
    // "H", True -> Some(InsertSpace(Left))
    // "L", True -> Some(InsertSpace(Right))
    // "J", True -> Some(InsertLine(Above))
    // "K", True -> Some(InsertLine(Below))
    // "h", True -> Some(Reorder(Left))
    // "l", True -> Some(Reorder(Right))
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
    #(_, Function(_, body)), [0, ..rest] -> get_node(body, rest)
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
    Function(var, body), [0, ..rest] ->
      ast.function(var, map_node(body, rest, mapper))
  }
  //     [] -> replacement
  //     [index, ..rest] ->
  //       case tree {
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
