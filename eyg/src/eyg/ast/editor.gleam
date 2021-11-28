import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer.{Metadata}
import eyg/typer/monotype
import eyg/typer/polytype.{State}
import eyg/codegen/javascript
import standard/example

pub type Mode {
  Command
  Draft(content: String)
  Select(options: List(String))
}

pub type Editor {
  Editor(
    tree: e.Expression(Metadata),
    typer: State,
    // position exist even in draft and select mode, it's where things get placed
    position: List(Int),
    mode: Mode,
  )
}

pub fn is_command(editor) {
  case editor {
    Editor(mode: Command, ..) -> True
    _ -> False
  }
}

pub fn is_draft(editor) {
  case editor {
    Editor(mode: Draft(_), ..) -> True
    _ -> False
  }
}

pub fn is_select(editor) {
  case editor {
    Editor(mode: Select(_), ..) -> True
    _ -> False
  }
}

pub fn in_scope(editor) {
  let Editor(tree: tree, position: position, ..) = editor
  case get_element(tree, position) {
    Expression(#(metadata, _)) ->
      list.map(metadata.scope, fn(x: #(String, polytype.Polytype)) { x.0 })
    _ -> []
  }
}

fn expression_type(expression: e.Expression(Metadata), typer: polytype.State) {
  let #(metadata, _) = expression
  case metadata.type_ {
    Ok(t) -> #(
      False,
      monotype.resolve(t, typer.substitutions)
      |> monotype.to_string(),
    )
    Error(reason) -> #(True, typer.reason_to_string(reason))
  }
}

pub fn target_type(editor) {
  let Editor(tree: tree, typer: typer, position: position, ..) = editor
  // can leave active on manipulation and just pull path on search for active, would make beginning of transform very inefficient as would involve a search
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, value, _))) -> expression_type(value, typer)
    Expression(expression) -> expression_type(expression, typer)
    _ -> #(False, "")
  }
}

pub fn init() {
  let untyped = example.simple()
  let position = []
  let #(typed, typer) = typer.infer_unconstrained(untyped)
  let mode = Command
  Editor(typed, typer, position, mode)
}

pub fn handle_click(editor: Editor, target) {
  case string.split(target, ":") {
    ["root"] -> Editor(..editor, position: [], mode: Command)
    ["p", rest] -> {
      let position =
        string.split(rest, ",")
        |> list.map(int.parse)
      case get_element(editor.tree, position) {
        Expression(#(_, e.Binary(content))) -> {
          let mode = Draft(content)
          Editor(..editor, position: position, mode: mode)
        }
        _ -> {
          let mode = Command
          Editor(..editor, position: position, mode: mode)
        }
      }
    }
    ["v", label] -> {
      let untyped =
        replace_node(editor.tree, editor.position, ast.variable(label))
      let #(typed, typer) = typer.infer_unconstrained(untyped)
      Editor(..editor, tree: typed, typer: typer, mode: Command)
    }

    _ -> todo("Error: never should have this as a click option")
  }
}

pub fn handle_keydown(editor, key, ctrl_key) {
  let Editor(tree: tree, typer: typer, position: position, mode: mode) = editor
  case mode {
    Command -> {
      let #(untyped, position, mode) =
        handle_transformation(tree, position, key, ctrl_key)
      let #(typed, typer) = case untyped {
        None -> #(tree, typer)
        Some(untyped) -> typer.infer_unconstrained(untyped)
      }
      Editor(
        ..editor,
        tree: typed,
        typer: typer,
        position: position,
        mode: mode,
      )
    }
    Draft(_) -> todo("handle draft mode")
  }
}

pub fn handle_change(editor, content) {
  let Editor(tree: tree, position: position, ..) = editor
  let untyped = case get_element(tree, position) {
    Expression(#(_, e.Binary(_))) -> {
      let new = ast.binary(content)
      replace_node(tree, position, new)
    }
    Pattern(p.Discard) | Pattern(p.Variable(_)) ->
      replace_pattern(tree, position, p.Variable(content))
    PatternElement(i, _) -> {
      let Some(#(pattern_position, _)) = parent_path(position)
      let Pattern(p.Tuple(elements)) = get_element(tree, pattern_position)
      let pre = list.take(elements, i)
      let [_, ..post] = list.drop(elements, i)
      let elements = list.flatten([pre, [Some(content)], post])
      replace_pattern(tree, pattern_position, p.Tuple(elements))
    }
    _ -> todo("change isn't handled on this element")
  }
  let #(typed, typer) = typer.infer_unconstrained(untyped)
  Editor(..editor, tree: typed, typer: typer, mode: Command)
}

pub type Element {
  Expression(e.Expression(Metadata))
  Pattern(p.Pattern)
  PatternElement(Int, Option(String))
}

pub fn multiline(fields) {
  list.length(fields) > 1
}

// TODO write up argument for identity function https://dev.to/rekreanto/why-it-is-impossible-to-write-an-identity-function-in-javascript-and-how-to-do-it-anyway-2j51#section-1
external fn untype(e.Expression(a)) -> e.Expression(Nil) =
  "../../harness.js" "identity"

fn handle_transformation(
  tree: e.Expression(Metadata),
  position,
  key,
  ctrl_key,
) -> #(Option(e.Expression(Nil)), List(Int), Mode) {
  case key, ctrl_key {
    // move
    "a", False -> navigation(increase_selection(tree, position))
    "s", False -> decrease_selection(tree, position)
    "h", False -> navigation(move_left(tree, position))
    "l", False -> navigation(move_right(tree, position))
    "j", False -> navigation(move_down(tree, position))
    "k", False -> navigation(move_up(tree, position))
    // transform
    "H", False -> command(space_left(tree, position))
    "L", False -> command(space_right(tree, position))
    "J", False -> command(space_below(tree, position))
    "K", False -> command(space_above(tree, position))
    "h", True -> command(drag_left(tree, position))
    "l", True -> command(drag_right(tree, position))
    "j", True -> command(drag_down(tree, position))
    "k", True -> command(drag_up(tree, position))
    // row
    "b", False -> command(create_binary(tree, position))
    "t", False -> command(wrap_tuple(tree, position))
    "e", False -> command(wrap_assignment(tree, position))
    "f", False -> command(wrap_function(tree, position))
    "u", False -> command(unwrap(tree, position))
    // don't wrap in anything if modifies everything
    "c", False -> call(tree, position)
    "d", False -> delete(tree, position)
    // modes
    "i", False -> draft(tree, position)
    // Fallback
    "Control", _ | "Shift", _ | "Alt", _ | "Meta", _ -> #(
      None,
      position,
      Command,
    )
    _, _ -> {
      io.debug(string.join(["No edit action for key: ", key]))
      #(None, position, Command)
    }
  }
}

fn navigation(position) {
  #(None, position, Command)
}

fn command(result) {
  let #(tree, position) = result
  #(Some(tree), position, Command)
}

fn increase_selection(tree, position) {
  let position = case parent_path(position) {
    Some(#(position, _)) -> position
    None -> []
  }
}

fn decrease_selection(tree, position) {
  let inner = ast.append_path(position, 0)
  case get_element(tree, position) {
    Expression(#(_, e.Tuple([]))) -> {
      let new = ast.tuple_([ast.hole()])
      #(Some(replace_node(tree, position, new)), inner, Command)
    }
    // TODO option of having a virtual node when you move down
    Expression(#(_, e.Row([]))) -> {
      let new = ast.row([#("ss", ast.hole())])
      #(Some(replace_node(tree, position, new)), inner, Command)
    }
    Expression(#(_, e.Binary(_))) | Expression(#(_, e.Variable(_))) -> #(
      None,
      position,
      Command,
    )
    Expression(_) -> #(None, inner, Command)
    Pattern(p.Tuple([])) -> #(
      Some(replace_pattern(tree, position, p.Tuple([None]))),
      inner,
      Command,
    )
    Pattern(p.Tuple(_)) | Pattern(p.Row(_)) -> #(None, inner, Command)
    _ -> #(None, position, Command)
  }
}

fn move_left(tree, position) {
  case list.reverse(position) {
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
}

fn move_right(tree, position) {
  case list.reverse(position) {
    [] -> {
      io.debug("cannot move right from root note")
      position
    }
    [index, ..rest] -> list.reverse([index + 1, ..rest])
  }
}

// TODO not very sure how this works
fn move_up(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) ->
      case parent_path(position) {
        Some(#(p, _)) -> p
        None -> position
      }
    _ ->
      case parent_let(tree, position) {
        None -> position
        Some(#(p, 0)) | Some(#(p, 1)) ->
          case parent_path(p) {
            Some(#(p, _)) -> p
            None -> p
          }
        Some(#(p, 2)) -> p
      }
  }
}

// TODO handle moving into blocks
fn move_down(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) -> ast.append_path(position, 2)

    _ ->
      case parent_let(tree, position) {
        None -> position
        Some(#(position, 0)) | Some(#(position, 1)) ->
          ast.append_path(position, 2)
        Some(#(position, 2)) ->
          case block_container(tree, position) {
            // Select whole bottom line
            None -> ast.append_path(position, 2)
            Some(position) -> move_down(tree, position)
          }
      }
  }
}

// Considered doing nothing in the case that the target element was already blank
// Decided against to keep code simpler
fn space_left(tree, position) {
  case closest(tree, position, match_tuple) {
    None -> #(untype(tree), position)
    Some(#(position, cursor, TupleExpression(elements))) -> {
      let pre = list.take(elements, cursor)
      let post = list.drop(elements, cursor)
      let elements = list.flatten([pre, [ast.hole()], post])
      let new = ast.tuple_(elements)
      #(replace_node(tree, position, new), ast.append_path(position, cursor))
    }
    Some(#(position, cursor, TuplePattern(elements))) -> {
      let pre = list.take(elements, cursor)
      let post = list.drop(elements, cursor)
      let elements = list.flatten([pre, [None], post])
      let new = p.Tuple(elements)
      #(replace_pattern(tree, position, new), ast.append_path(position, cursor))
    }
  }
}

fn space_right(tree, position) {
  case closest(tree, position, match_tuple) {
    None -> #(untype(tree), position)
    Some(#(position, cursor, TupleExpression(elements))) -> {
      let cursor = cursor + 1
      let pre = list.take(elements, cursor)
      let post = list.drop(elements, cursor)
      let elements = list.flatten([pre, [ast.hole()], post])
      let new = ast.tuple_(elements)
      #(replace_node(tree, position, new), ast.append_path(position, cursor))
    }
    Some(#(position, cursor, TuplePattern(elements))) -> {
      let cursor = cursor + 1
      let pre = list.take(elements, cursor)
      let post = list.drop(elements, cursor)
      let elements = list.flatten([pre, [None], post])
      let new = p.Tuple(elements)
      #(replace_pattern(tree, position, new), ast.append_path(position, cursor))
    }
  }
}

fn space_below(tree, position) {
  case closest(tree, position, match_let) {
    None -> #(ast.let_(p.Discard, untype(tree), ast.hole()), [2])
    Some(#(path, 2, #(pattern, value, then))) -> {
      let new = ast.let_(pattern, value, ast.let_(p.Discard, then, ast.hole()))
      #(
        replace_node(tree, path, new),
        ast.append_path(ast.append_path(path, 2), 2),
      )
    }
    Some(#(path, _, #(pattern, value, then))) -> {
      let new = ast.let_(pattern, value, ast.let_(p.Discard, ast.hole(), then))
      #(
        replace_node(tree, path, new),
        ast.append_path(ast.append_path(path, 2), 0),
      )
    }
  }
}

fn space_above(tree, position) {
  case closest(tree, position, match_let) {
    None -> #(ast.let_(p.Discard, ast.hole(), untype(tree)), [0])
    Some(#(path, 2, #(pattern, value, then))) -> {
      let new = ast.let_(pattern, value, ast.let_(p.Discard, ast.hole(), then))
      #(
        replace_node(tree, path, new),
        ast.append_path(ast.append_path(path, 2), 0),
      )
    }
    Some(#(path, _, #(pattern, value, then))) -> {
      let new = ast.let_(p.Discard, ast.hole(), ast.let_(pattern, value, then))
      #(replace_node(tree, path, new), ast.append_path(path, 0))
    }
  }
}

fn drag_left(tree, position) {
  case closest(tree, position, match_tuple) {
    None -> #(untype(tree), position)
    Some(#(position, cursor, match)) ->
      case cursor > 0 {
        False -> #(untype(tree), ast.append_path(position, 0))
        True ->
          case match {
            TupleExpression(elements) -> {
              let pre = list.take(elements, cursor - 1)
              let [me, neighbour, ..post] = list.drop(elements, cursor - 1)
              let elements = list.flatten([pre, [neighbour, me], post])
              let new = ast.tuple_(elements)
              #(
                replace_node(tree, position, new),
                ast.append_path(position, cursor - 1),
              )
            }
            TuplePattern(elements) -> {
              let pre = list.take(elements, cursor - 1)
              let [me, neighbour, ..post] = list.drop(elements, cursor - 1)
              let elements = list.flatten([pre, [neighbour, me], post])
              let new = p.Tuple(elements)
              #(
                replace_pattern(tree, position, new),
                ast.append_path(position, cursor - 1),
              )
            }
          }
      }
  }
}

fn drag_right(tree, position) {
  case closest(tree, position, match_tuple) {
    None -> #(untype(tree), position)
    Some(#(position, cursor, TupleExpression(elements))) ->
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
    Some(#(position, cursor, TuplePattern(elements))) ->
      case cursor + 1 < list.length(elements) {
        False -> #(untype(tree), ast.append_path(position, cursor))
        True -> {
          let pre = list.take(elements, cursor)
          let [me, neighbour, ..post] = list.drop(elements, cursor)
          let elements = list.flatten([pre, [neighbour, me], post])
          let new = p.Tuple(elements)
          #(
            replace_pattern(tree, position, new),
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

type TupleMatch {
  TupleExpression(elements: List(e.Expression(Nil)))
  TuplePattern(elements: List(Option(String)))
}

fn match_tuple(target) -> Result(TupleMatch, Nil) {
  case target {
    Expression(#(_, e.Tuple(elements))) ->
      Ok(TupleExpression(list.map(elements, untype)))
    Pattern(p.Tuple(elements)) -> Ok(TuplePattern(elements))
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
    None -> #(ast.let_(p.Discard, untype(tree), ast.hole()), [0])
    // I don't support let in let yet
    Some(#(position, 2, #(pattern, value, then))) -> {
      let new = ast.let_(pattern, value, ast.let_(p.Discard, then, ast.hole()))
      #(
        replace_node(tree, position, new),
        ast.append_path(ast.append_path(position, 2), 0),
      )
    }
    _ -> #(untype(tree), position)
  }
}

fn create_binary(tree, position) {
  let hole_func = ast.generate_hole

  case get_element(tree, position) {
    Expression(#(_, e.Provider(_, g))) if g == hole_func -> {
      let new = ast.binary("")
      #(replace_node(tree, position, new), position)
    }
    _ -> #(untype(tree), position)
  }
}

fn wrap_tuple(tree, position) {
  let target = get_element(tree, position)
  // TODO don't wrap multi line terms
  let hole_func = ast.generate_hole
  case target {
    Expression(#(_, e.Provider(_, g))) if g == hole_func -> {
      let new = ast.tuple_([])
      #(replace_node(tree, position, new), position)
    }
    Expression(expression) -> {
      let new = ast.tuple_([untype(expression)])
      #(replace_node(tree, position, new), ast.append_path(position, 0))
    }
    Pattern(p.Variable(label)) -> #(
      replace_pattern(tree, position, p.Tuple([Some(label)])),
      ast.append_path(position, 0),
    )
    Pattern(p.Discard) -> #(
      replace_pattern(tree, position, p.Tuple([])),
      position,
    )
    PatternElement(_, _) | Pattern(_) -> #(untype(tree), position)
  }
}

fn wrap_function(tree, position) {
  case get_element(tree, position) {
    Expression(expression) -> {
      let new = ast.function(p.Discard, untype(expression))
      #(replace_node(tree, position, new), ast.append_path(position, 0))
    }
    _ -> #(untype(tree), position)
  }
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
          let pattern = case label {
            Some(label) -> p.Variable(label)
            None -> p.Discard
          }
          let new = ast.let_(pattern, untype(value), untype(then))
          let modified = replace_node(tree, parent_position, new)
          #(modified, list.append(parent_position, [0]))
        }
      }
    }
  }
}

fn call(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) -> #(None, position, Command)
    Expression(expression) -> {
      let new = ast.call(untype(expression), ast.hole())
      let modified = replace_node(tree, position, new)
      #(Some(modified), list.append(position, [1]), Command)
    }
    _ -> #(None, position, Command)
  }
}

fn delete(tree, position) {
  let hole_func = ast.generate_hole
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, then))) -> #(
      Some(replace_node(tree, position, untype(then))),
      position,
      Select([]),
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
              #(
                Some(replace_node(tree, p_path, ast.tuple_(elements))),
                p_path,
                Command,
              )
            }
            _ -> #(None, position, Select([]))
          }
        None -> #(None, position, Select([]))
      }
    Expression(_) -> #(
      Some(replace_node(tree, position, ast.hole())),
      position,
      Select([]),
    )
    Pattern(_) -> #(
      Some(replace_pattern(tree, position, p.Discard)),
      position,
      Command,
    )
    PatternElement(cursor, el) -> {
      let Some(#(pattern_position, _)) = parent_path(position)
      let Pattern(p.Tuple(elements)) = get_element(tree, pattern_position)
      let pre = list.take(elements, cursor)
      let post = list.drop(elements, cursor + 1)
      let insert = case el {
        None -> []
        Some(_) -> [None]
      }
      let elements = list.flatten([pre, insert, post])
      let position = case list.length(elements) > 0, cursor > 0 && list.length(
        insert,
      ) == 0 {
        False, _ -> pattern_position
        _, True -> ast.append_path(pattern_position, cursor - 1)
        _, False -> ast.append_path(pattern_position, cursor)
      }
      #(
        Some(replace_pattern(tree, pattern_position, p.Tuple(elements))),
        position,
        Command,
      )
    }
  }
}

fn draft(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Binary(content))) -> #(None, position, Draft(content))
    Pattern(p.Discard) -> #(None, position, Draft(""))
    Pattern(p.Variable(label)) -> #(None, position, Draft(label))
    PatternElement(_, None) -> #(None, position, Draft(""))
    PatternElement(_, Some(label)) -> #(None, position, Draft(label))
    _ -> #(None, position, Command)
  }
}

fn replace_pattern(tree, position, pattern) {
  // while we don't have arbitrary nesting in patterns don't update replace node, instead
  // manually step up once
  let Some(#(let_position, 0)) = parent_path(position)
  case get_element(tree, let_position) {
    Expression(#(_, e.Let(_, value, then))) -> {
      let new = ast.let_(pattern, untype(value), untype(then))
      replace_node(tree, let_position, new)
    }
    Expression(#(_, e.Function(_, body))) -> {
      let new = ast.function(pattern, untype(body))
      replace_node(tree, let_position, new)
    }
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
    #(_, e.Row(fields)), [i, ..rest] -> {
      let [#(_, child), .._] = list.drop(fields, i)
      get_element(child, rest)
    }
    #(_, e.Let(pattern, _, _)), [0] -> Pattern(pattern)
    #(_, e.Let(p.Tuple(elements), _, _)), [0, i] -> {
      // l.at and this should be an error instead
      let [element, .._] = list.drop(elements, i)
      PatternElement(i, element)
    }
    #(_, e.Let(_, value, _)), [1, ..rest] -> get_element(value, rest)
    #(_, e.Let(_, _, then)), [2, ..rest] -> get_element(then, rest)
    #(_, e.Function(pattern, _)), [0] -> Pattern(pattern)
    #(_, e.Function(p.Tuple(elements), _)), [0, i] -> {
      // l.at and this should be an error instead
      let [element, .._] = list.drop(elements, i)
      PatternElement(i, element)
    }
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
    e.Row(fields), [index, ..rest] -> {
      let pre =
        list.take(fields, index)
        |> list.map(fn(x) {
          let #(k, v) = x
          #(k, untype(v))
        })
      let [#(k, current), ..post] = list.drop(fields, index)
      let post =
        list.map(
          post,
          fn(x) {
            let #(k, v) = x
            #(k, untype(v))
          },
        )
      let updated = map_node(current, rest, mapper)
      let fields = list.flatten([pre, [#(k, updated)], post])
      ast.row(fields)
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
