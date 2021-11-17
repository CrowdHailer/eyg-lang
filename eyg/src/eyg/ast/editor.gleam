import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer.{Metadata}
import eyg/typer/monotype
import eyg/typer/polytype.{State}

pub type Element {
  Expression(e.Expression(Metadata))
  Pattern(p.Pattern)
  PatternElement(Int, String)
}

// TODO write up argument for identity function https://dev.to/rekreanto/why-it-is-impossible-to-write-an-identity-function-in-javascript-and-how-to-do-it-anyway-2j51#section-1
external fn untype(e.Expression(a)) -> e.Expression(Nil) =
  "../../harness.js" "identity"

pub fn handle_keydown(
  tree: e.Expression(Metadata),
  position,
  key,
  typer,
) -> #(e.Expression(Nil), List(Int)) {
  case key {
    "a" -> increase_selection(tree, position)
    "s" -> decrease_selection(tree, position)
    "h" -> move_left(tree, position)
    "l" -> move_right(tree, position)
    "j" -> move_down(tree, position)
    "k" -> move_up(tree, position)
    "t" -> wrap_tuple(tree, position)
    "u" -> unwrap(tree, position)
    "c" -> call(tree, position, typer)
    "d" -> delete(tree, position)
    _ -> {
      io.debug("No edit action for this key")
      #(untype(tree), position)
    }
  }
}

pub fn handle_contentedited(
  tree,
  position,
  content,
) -> #(e.Expression(Nil), List(Int)) {
  let target = get_element(tree, position)
  case target {
    Expression(#(_, e.Binary(_))) -> {
      let modified = replace_node(tree, position, ast.binary(content))
      #(modified, position)
    }
  }
}

fn increase_selection(tree, position) {
  let position = case parent_path(position) {
    Some(#(position, _)) -> position
    None -> []
  }
  #(untype(tree), position)
}

fn decrease_selection(tree, position) {
  #(untype(tree), ast.append_path(position, 0))
}

fn move_left(tree, position) {
  let position = case list.reverse(position) {
    [] -> {
      io.debug("cannot move left from root note")
      position
    }
    [0, .._] -> {
      io.debug("cannot move any further left")
      position
    }
    [index, ..rest] -> list.reverse([index - 1, ..rest])
  }
  #(untype(tree), position)
}

fn move_right(tree, position) {
  let position = case list.reverse(position) {
    [] -> {
      io.debug("cannot move right from root note")
      position
    }
    [index, ..rest] -> list.reverse([index + 1, ..rest])
  }
  #(untype(tree), position)
}

// TODO not very sure how this works
fn move_up(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) -> {
      io.debug("leeet")
      let path = case parent_path(position) {
        Some(#(p, _)) -> p
        None -> position
      }
      io.debug(position)
      io.debug(path)
      #(untype(tree), position)
    }
    _ ->
      case parent_let(tree, position) {
        None -> #(untype(tree), position)
        Some(#(position, 0)) | Some(#(position, 1)) -> #(
          untype(tree),
          ast.append_path(position, 2),
        )
        Some(#(position, 2)) ->
          case block_container(tree, position) {
            // Select whole bottom line
            None -> #(untype(tree), ast.append_path(position, 2))
            Some(position) -> move_down(tree, position)
          }
      }
  }
}

// TODO handle moving into blocks
fn move_down(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) -> #(
      untype(tree),
      ast.append_path(position, 2),
    )
    _ ->
      case parent_let(tree, position) {
        None -> #(untype(tree), position)
        Some(#(position, 0)) | Some(#(position, 1)) -> #(
          untype(tree),
          ast.append_path(position, 2),
        )
        Some(#(position, 2)) ->
          case block_container(tree, position) {
            // Select whole bottom line
            None -> #(untype(tree), ast.append_path(position, 2))
            Some(position) -> move_down(tree, position)
          }
      }
  }
}

fn parent_let(tree, position) {
  case parent_path(position) {
    None -> None
    Some(#(position, index)) ->
      case get_element(tree, position) {
        Expression(#(_, e.Let(_, _, _))) -> Some(#(position, index))
        _ -> parent_let(tree, position)
      }
  }
}

fn block_container(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) ->
      case parent_path(position) {
        None -> None
        Some(#(position, _)) -> block_container(tree, position)
      }
    Expression(expression) -> Some(position)
  }
}

fn wrap_tuple(tree, position) {
  let target = get_element(tree, position)
  // TODO don't wrap multi line terms
  let modified = case target {
    Expression(expression) ->
      replace_node(tree, position, ast.tuple_([untype(expression)]))
    Pattern(p.Variable(label)) -> {
      assert Some(#(path, _)) = parent_path(position)
      assert Expression(#(_, e.Let(_, value, then))) = get_element(tree, path)
      let new = ast.let_(p.Tuple([label]), untype(value), untype(then))
      replace_node(tree, path, new)
    }
  }
  #(modified, ast.append_path(position, 0))
}

fn unwrap(tree, position) {
  case parent_path(position) {
    None -> #(untype(tree), position)
    Some(#(parent_position, index)) -> {
      let parent = get_element(tree, parent_position)
      case parent {
        Expression(#(_, e.Tuple(elements))) -> {
          let [replacement, .._] = list.drop(elements, index)
          let modified =
            replace_node(tree, parent_position, untype(replacement))
          #(modified, parent_position)
        }
        Expression(#(_, e.Call(func, with))) -> {
          let replacement = case index {
            0 -> func
            1 -> with
          }
          let modified =
            replace_node(tree, parent_position, untype(replacement))
          #(modified, parent_position)
        }
        Expression(_) -> unwrap(tree, position)
        Pattern(p.Tuple(elements)) -> {
          let [label, .._] = list.drop(elements, index)
          assert Some(#(parent_position, _)) = parent_path(parent_position)
          assert Expression(#(_, e.Let(_, value, then))) =
            get_element(tree, parent_position)
          let new = ast.let_(p.Variable(label), untype(value), untype(then))
          let modified = replace_node(tree, parent_position, new)
          #(modified, list.append(parent_position, [0]))
        }
      }
    }
  }
}

fn call(tree, position, typer) {
  let Expression(expression) = get_element(tree, position)
  let #(Metadata(type_: type_, ..), _node) = expression
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = type_
  let arg_count = monotype.how_many_args(monotype.resolve(type_, substitutions))
  // TODO arg count
  let new = ast.call(untype(expression), ast.tuple_([]))
  let modified = replace_node(tree, position, new)
  #(modified, list.append(position, [1, 0]))
}

fn delete(tree, position) {
  let replacement = case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, then))) -> untype(then)
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
  tree: e.Expression(a),
  path: List(Int),
  replacement: e.Expression(Nil),
) -> e.Expression(Nil) {
  let tree = untype(tree)
  map_node(tree, path, fn(_) { replacement })
}

pub fn map_node(
  tree: e.Expression(a),
  path: List(Int),
  mapper: fn(e.Expression(a)) -> e.Expression(Nil),
) -> e.Expression(Nil) {
  let #(_, node) = tree
  io.debug(node)
  case node, path {
    _, [] -> mapper(tree)
    e.Tuple(elements), [index, ..rest] -> {
      let pre =
        list.take(elements, index)
        |> list.map(untype)
      let [current, ..post] = list.drop(elements, index)
      let post = list.map(post, untype)
      let updated = map_node(current, rest, mapper)
      let elements = list.flatten([pre, [updated], post])
      ast.tuple_(elements)
    }
    e.Let(pattern, value, then), [1, ..rest] ->
      ast.let_(pattern, map_node(value, rest, mapper), untype(then))
    e.Let(pattern, value, then), [2, ..rest] ->
      ast.let_(pattern, untype(value), map_node(then, rest, mapper))
    e.Function(pattern, body), [1, ..rest] ->
      ast.function(pattern, map_node(body, rest, mapper))
    e.Call(func, with), [0, ..rest] ->
      ast.call(map_node(func, rest, mapper), untype(with))
    e.Call(func, with), [1, ..rest] ->
      ast.call(untype(func), map_node(with, rest, mapper))

    _, _ -> {
      io.debug(node)
      io.debug(path)
      todo("unhandled node map")
    }
  }
}
