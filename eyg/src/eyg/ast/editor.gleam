import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
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
  ctrl_key,
  typer,
) -> #(e.Expression(Nil), List(Int)) {
  case key, ctrl_key {
    "a", False -> increase_selection(tree, position)
    "s", False -> decrease_selection(tree, position)
    "h", False -> move_left(tree, position)
    "l", False -> move_right(tree, position)
    "j", False -> move_down(tree, position)
    "k", False -> move_up(tree, position)
    "H", False -> space_left(tree, position)
    "L", False -> space_right(tree, position)
    "J", False -> space_below(tree, position)
    "K", False -> space_above(tree, position)
    "h", True -> drag_left(tree, position)
    "l", True -> drag_right(tree, position)
    "j", True -> drag_down(tree, position)
    "k", True -> drag_up(tree, position)
    "e", False -> wrap_assignment(tree, position)
    // row
    "t", False -> wrap_tuple(tree, position)
    "u", False -> unwrap(tree, position)
    "c", False -> call(tree, position, typer)
    "d", False -> delete(tree, position)
    "Control", _ | "Shift", _ | "Alt", _ | "Meta", _ -> #(
      untype(tree),
      position,
    )
    _, _ -> {
      io.debug(string.join(["No edit action for key: ", key]))
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

// TODO If already a space don't go again
// TODO implement for patterns
fn space_left(tree, position) {
  case closest(tree, position, match_tuple) {
    None -> #(untype(tree), position)
    Some(#(position, cursor, elements)) -> {
      let pre = list.take(elements, cursor)
      let post = list.drop(elements, cursor)
      let elements = list.flatten([pre, [ast.hole()], post])
      let new = ast.tuple_(elements)
      #(replace_node(tree, position, new), ast.append_path(position, cursor))
    }
  }
}

fn space_right(tree, position) {
  case closest(tree, position, match_tuple) {
    None -> #(untype(tree), position)
    Some(#(position, cursor, elements)) -> {
      let cursor = cursor + 1
      let pre = list.take(elements, cursor)
      let post = list.drop(elements, cursor)
      let elements = list.flatten([pre, [ast.hole()], post])
      let new = ast.tuple_(elements)
      #(replace_node(tree, position, new), ast.append_path(position, cursor))
    }
  }
}

fn space_below(tree, position) {
  case closest(tree, position, match_let) {
    None -> #(ast.let_(p.Variable(""), untype(tree), ast.hole()), [2])
    Some(#(path, 2, #(pattern, value, then))) -> {
      let new =
        ast.let_(pattern, value, ast.let_(p.Variable(""), then, ast.hole()))
      #(
        replace_node(tree, path, new),
        ast.append_path(ast.append_path(path, 2), 2),
      )
    }
    Some(#(path, _, #(pattern, value, then))) -> {
      let new =
        ast.let_(pattern, value, ast.let_(p.Variable(""), ast.hole(), then))
      #(
        replace_node(tree, path, new),
        ast.append_path(ast.append_path(path, 2), 0),
      )
    }
  }
}

fn space_above(tree, position) {
  case closest(tree, position, match_let) {
    None -> #(ast.let_(p.Variable(""), ast.hole(), untype(tree)), [0])
    Some(#(path, 2, #(pattern, value, then))) -> {
      let new =
        ast.let_(pattern, value, ast.let_(p.Variable(""), ast.hole(), then))
      #(
        replace_node(tree, path, new),
        ast.append_path(ast.append_path(path, 2), 0),
      )
    }
    Some(#(path, _, #(pattern, value, then))) -> {
      let new =
        ast.let_(p.Variable(""), ast.hole(), ast.let_(pattern, value, then))
      #(replace_node(tree, path, new), ast.append_path(path, 0))
    }
  }
}

fn drag_left(tree, position) {
  case closest(tree, position, match_tuple) {
    None -> #(untype(tree), position)
    Some(#(position, cursor, elements)) ->
      case cursor > 0 {
        False -> #(untype(tree), ast.append_path(position, 0))
        True -> {
          let pre = list.take(elements, cursor - 1)
          let [me, neighbour, ..post] = list.drop(elements, cursor - 1)
          let elements = list.flatten([pre, [neighbour, me], post])
          let new = ast.tuple_(elements)
          #(
            replace_node(tree, position, new),
            ast.append_path(position, cursor - 1),
          )
        }
      }
  }
}

fn drag_right(tree, position) {
  case closest(tree, position, match_tuple) {
    None -> #(untype(tree), position)
    Some(#(position, cursor, elements)) ->
      case cursor + 1 < list.length(elements) {
        False -> #(untype(tree), ast.append_path(position, cursor))
        True -> {
          let pre = list.take(elements, cursor)
          let [me, neighbour, ..post] = list.drop(elements, cursor)
          let elements = list.flatten([pre, [neighbour, me], post])
          let new = ast.tuple_(elements)
          #(
            replace_node(tree, position, new),
            ast.append_path(position, cursor + 1),
          )
        }
      }
  }
}

fn drag_down(tree, position) {
  case closest(tree, position, match_let) {
    None -> #(untype(tree), position)
    Some(#(path, 2, #(pattern, value, then))) -> // leave as is, can't drag past un assigned
    #(untype(tree), position)
    Some(#(path, _, #(pattern, value, #(_, e.Let(p_after, v_after, then))))) -> {
      let new = ast.let_(p_after, v_after, ast.let_(pattern, value, then))
      #(
        replace_node(tree, path, new),
        ast.append_path(ast.append_path(path, 2), 0),
      )
    }
    _ -> #(untype(tree), position)
  }
}

fn drag_up(tree, original) {
  case closest(tree, original, match_let) {
    None -> #(untype(tree), original)
    Some(#(position, 2, #(pattern, value, then))) -> // leave as is, would meet a 0/1 node first if dragable.
    #(untype(tree), original)
    Some(#(position, _, #(pattern, value, then))) ->
      case parent_path(position) {
        None -> #(untype(tree), original)
        Some(#(position, _)) ->
          case get_element(tree, position) {
            Expression(#(_, e.Let(p_before, v_before, _))) -> {
              let new =
                ast.let_(
                  pattern,
                  untype(value),
                  ast.let_(p_before, untype(v_before), then),
                )
              #(replace_node(tree, position, new), ast.append_path(position, 0))
            }
            _ -> #(untype(tree), original)
          }
      }
  }
}

fn match_tuple(target) {
  case target {
    Expression(#(_, e.Tuple(elements))) -> Ok(list.map(elements, untype))
    _ -> Error(Nil)
  }
}

fn match_let(target) {
  case target {
    Expression(#(_, e.Let(p, v, t))) -> Ok(#(p, untype(v), untype(t)))
    _ -> Error(Nil)
  }
}

fn closest(
  tree,
  position,
  search: fn(Element) -> Result(t, Nil),
) -> Option(#(List(Int), Int, t)) {
  case parent_path(position) {
    None -> None
    Some(#(position, index)) ->
      case search(get_element(tree, position)) {
        Ok(x) -> Some(#(position, index, x))
        Error(_) -> closest(tree, position, search)
      }
  }
}

fn parent_let(tree, position) {
  case closest(tree, position, match_let) {
    Some(#(path, cursor, _)) -> Some(#(path, cursor))
    None -> None
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

fn wrap_assignment(tree, position) {
  // TODO if already on a let this comes up with a two but it shouldn't
  case closest(tree, position, match_let) {
    None -> #(ast.let_(p.Variable(""), untype(tree), ast.hole()), [0])
    // I don't support let in let yet
    Some(#(position, 2, #(pattern, value, then))) -> {
      let new =
        ast.let_(pattern, value, ast.let_(p.Variable(""), then, ast.hole()))
      #(
        replace_node(tree, position, new),
        ast.append_path(ast.append_path(position, 2), 0),
      )
    }
    _ -> #(untype(tree), position)
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
  let hole_func = ast.generate_hole
  let replacement = case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, then))) -> #(
      replace_node(tree, position, untype(then)),
      position,
    )
    Expression(#(_, e.Provider(_, g))) if g == hole_func ->
      case parent_path(position) {
        Some(#(p_path, cursor)) ->
          case get_element(tree, p_path) {
            Expression(#(_, e.Tuple(elements))) -> {
              let pre = list.take(elements, cursor)
              let post = list.drop(elements, cursor + 1)
              let elements =
                list.append(pre, post)
                |> list.map(untype)
              #(replace_node(tree, p_path, ast.tuple_(elements)), p_path)
            }
            _ -> #(untype(tree), position)
          }
        None -> #(untype(tree), position)
      }
    Expression(_) -> #(replace_node(tree, position, ast.hole()), position)
  }
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
