import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/order
import gleam/string
import eyg/ast
import eyg/ast/provider
import eyg/ast/encode
import eyg/ast/path
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer.{Metadata}
import eyg/typer/monotype as t
import eyg/typer/polytype
import eyg/codegen/javascript
import standard/example

pub type Mode {
  Command
  Draft(content: String)
  Select(choices: List(String))
}

pub type Editor {
  Editor(
    tree: e.Expression(Metadata, e.Expression(Metadata, Dynamic)),
    typer: typer.Typer,
    selection: Option(List(Int)),
    mode: Mode,
    expanded: Bool,
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

fn expression_type(expression: e.Expression(Metadata, a), typer: typer.Typer) {
  let #(metadata, _) = expression
  case metadata.type_ {
    Ok(t) -> #(
      False,
      t.resolve(t, typer.substitutions)
      |> t.to_string(),
    )
    Error(reason) -> #(True, typer.reason_to_string(reason, typer))
  }
}

// returns bool if error
pub fn target_type(editor) {
  let Editor(tree: tree, typer: typer, selection: selection, ..) = editor
  // can leave active on manipulation and just pull path on search for active, would make beginning of transform very inefficient as would involve a search
  case selection {
    Some(path) ->
      case get_element(tree, path) {
        Expression(#(_, e.Let(_, value, _))) -> expression_type(value, typer)
        Expression(expression) -> expression_type(expression, typer)
        _ -> #(False, "")
      }
    None -> #(False, "")
  }
}

pub fn is_selected(editor: Editor, path) {
  case editor.selection {
    Some(p) if p == path -> True
    _ -> False
  }
}

pub fn inconsistencies(editor) {
  let Editor(typer: t, ..) = editor
  list.sort(
    t.inconsistencies,
    fn(a, b) {
      let #(a_path, _) = a
      let #(b_path, _) = b
      path.order(a_path, b_path)
    },
  )
}

pub fn codegen(editor) {
  let Editor(tree: tree, typer: typer, ..) = editor
  let good = list.length(typer.inconsistencies) == 0
  let code = javascript.render_to_string(tree, typer)
  #(good, code)
}

// Can put harness as a single record type that is copied to the code bundle and passed in at the top
pub fn eval(editor) {
  let Editor(tree: tree, typer: typer, ..) = editor
  let True = list.length(typer.inconsistencies) == 0
  javascript.eval(tree, typer)
}

pub fn dump(editor) {
  let Editor(tree: tree, ..) = editor
  let dump =
    encode.to_json(tree)
    |> encode.json_to_string
  dump
}

pub fn init(raw) {
  let untyped = encode.from_json(encode.json_from_string(raw))
  // let untyped = example.minimal()
  let #(typed, typer) = typer.infer_unconstrained(untyped)
  let mode = Command
  Editor(typed, typer, None, mode, False)
}

fn rest_to_path(rest) {
  case rest {
    "" -> []
    _ ->
      // empty string makes unparsable as int list
      string.split(rest, ",")
      |> list.map(int.parse)
  }
}

// At the editor level we might want to handle semantic events like select node. And have display do handle click
pub fn handle_click(editor: Editor, target) {
  case string.split(target, ":") {
    ["root"] -> Editor(..editor, selection: Some([]), mode: Command)
    ["p", rest] -> {
      let path = rest_to_path(rest)
      Editor(..editor, selection: Some(path), mode: Command)
    }
  }
}

pub fn handle_keydown(editor, key, ctrl_key) {
  let Editor(tree: tree, typer: typer, selection: selection, mode: mode, ..) =
    editor
  let Some(path) = selection
  let new = case mode {
    Command ->
      case key {
        "x" -> {
          let Editor(expanded: expanded, ..) = editor
          // is there no gleam not
          let expanded = case expanded {
            True -> False
            False -> True
          }
          Editor(..editor, expanded: expanded)
        }
        _ -> {
          let #(untyped, path, mode) =
            handle_transformation(editor, path, key, ctrl_key)
          let #(typed, typer) = case untyped {
            None -> #(tree, typer)
            Some(untyped) -> typer.infer_unconstrained(untyped)
          }
          Editor(
            ..editor,
            tree: typed,
            typer: typer,
            selection: Some(path),
            mode: mode,
          )
        }
      }
    Draft(_) -> todo("handle draft mode")
    Select(_) ->
      case key {
        "Escape" -> Editor(..editor, mode: Command)
        _ -> todo("handle selection refinement")
      }
  }
  // crash if this doesn't work to get to handle_keydown error handling
  // if get_element in target_type always returned OK/Error we could probably work to remove the error handling
  // though is there any harm in the fall back currently in App.svelte?
  target_type(new)
  new
}

pub fn cancel_change(editor) {
  Editor(..editor, mode: Command)
}

pub fn handle_change(editor, content) {
  let Editor(tree: tree, selection: selection, ..) = editor
  let Some(position) = selection
  let untyped = case get_element(tree, position) {
    Expression(#(_, e.Binary(_))) -> {
      let new = ast.binary(content)
      replace_expression(tree, position, new)
    }

    Pattern(
      p.Variable(l1),
      #(
        _,
        e.Let(
          _alreadymatchedpattern,
          #(_, e.Function(p.Row([#(l2, "then")]), body)),
          then,
        ),
      ),
    ) if l1 == l2 -> {
      let Some(#(parent_position, _)) = parent_path(position)
      let new =
        ast.let_(
          p.Variable(content),
          ast.function(p.Row([#(content, "then")]), untype(body)),
          untype(then),
        )
      replace_expression(tree, parent_position, new)
    }
    Pattern(p.Discard, _) | Pattern(p.Variable(_), _) ->
      replace_pattern(tree, position, p.Variable(content))
    // Putting stuff in the pattern Element works
    PatternElement(i, _) -> {
      let Some(#(pattern_position, _)) = parent_path(position)
      let Pattern(p.Tuple(elements), _) = get_element(tree, pattern_position)
      let pre = list.take(elements, i)
      let [_, ..post] = list.drop(elements, i)
      let elements = list.flatten([pre, [Some(content)], post])
      replace_pattern(tree, pattern_position, p.Tuple(elements))
    }
    RowKey(i, _) -> {
      let Some(#(field_position, _)) = parent_path(position)
      let Some(#(record_position, _)) = parent_path(field_position)
      let Expression(#(_, e.Row(fields))) = get_element(tree, record_position)
      let pre =
        list.take(fields, i)
        |> list.map(untype_field)
      let [#(_, value), ..post] = list.drop(fields, i)
      let post =
        post
        |> list.map(untype_field)
      let fields = list.flatten([pre, [#(content, untype(value))], post])
      replace_expression(tree, record_position, ast.row(fields))
    }
    PatternKey(i, _) -> {
      let Some(#(field_position, _)) = parent_path(position)
      let Some(#(pattern_position, _)) = parent_path(field_position)
      let Pattern(p.Row(fields), _) = get_element(tree, pattern_position)
      // TODO map at
      let pre = list.take(fields, i)
      let [#(_, label), ..post] = list.drop(fields, i)
      let fields = list.flatten([pre, [#(content, label)], post])
      replace_pattern(tree, pattern_position, p.Row(fields))
    }
    PatternFieldBind(i, _) -> {
      let Some(#(field_position, _)) = parent_path(position)
      let Some(#(pattern_position, _)) = parent_path(field_position)
      let Pattern(p.Row(fields), _) = get_element(tree, pattern_position)
      // TODO map at
      let pre = list.take(fields, i)
      let [#(key, _), ..post] = list.drop(fields, i)
      let fields = list.flatten([pre, [#(key, content)], post])
      replace_pattern(tree, pattern_position, p.Row(fields))
    }
    ProviderGenerator(_) -> {
      let Some(#(provider_position, _)) = parent_path(position)
      let Expression(#(_, e.Provider(config, _, _))) =
        get_element(tree, provider_position)
      let new = ast.provider(config, e.generator_from_string(content))
      replace_expression(tree, provider_position, new)
    }
    ProviderConfig(_) -> {
      let Some(#(provider_position, _)) = parent_path(position)
      let Expression(#(_, e.Provider(_, generator, _))) =
        get_element(tree, provider_position)
      let new = ast.provider(content, generator)
      replace_expression(tree, provider_position, new)
    }
    Expression(_) -> {
      let new = ast.variable(content)
      replace_expression(tree, position, new)
    }
  }

  let #(typed, typer) = typer.infer_unconstrained(untyped)
  Editor(..editor, tree: typed, typer: typer, mode: Command)
}

pub type Element(a, b) {
  Expression(e.Expression(a, b))
  RowField(Int, #(String, e.Expression(a, b)))
  RowKey(Int, String)
  Pattern(p.Pattern, e.Expression(a, b))
  PatternElement(Int, Option(String))
  PatternField(Int, #(String, String))
  PatternKey(Int, String)
  PatternFieldBind(Int, String)
  ProviderGenerator(e.Generator)
  ProviderConfig(String)
}

external fn untype(e.Expression(a, b)) -> e.Expression(Dynamic, Dynamic) =
  "../../eyg_utils.js" "identity"

pub fn untype_field(
  field: #(String, e.Expression(a, b)),
) -> #(String, e.Expression(Dynamic, Dynamic)) {
  let #(label, value) = field
  #(label, untype(value))
}

fn handle_transformation(
  editor,
  position,
  key,
  ctrl_key,
) -> #(Option(e.Expression(Dynamic, Dynamic)), List(Int), Mode) {
  let Editor(tree: tree, ..) = editor
  let inconsistencies = inconsistencies(editor)
  case key, ctrl_key {
    // move
    "a", False -> navigation(increase_selection(tree, position))
    "s", False -> decrease_selection(tree, position)
    "h", False -> navigation(move_left(tree, position))
    "l", False -> navigation(move_right(tree, position))
    "j", False -> navigation(move_down(tree, position))
    "k", False -> navigation(move_up(tree, position))
    " ", False -> navigation(next_error(inconsistencies, position))
    // transform
    "H", False -> space_left(tree, position)
    "L", False -> space_right(tree, position)
    "J", False -> command(space_below(tree, position))
    "K", False -> command(space_above(tree, position))
    "h", True -> command(drag_left(tree, position))
    "l", True -> command(drag_right(tree, position))
    "j", True -> command(drag_down(tree, position))
    "k", True -> command(drag_up(tree, position))
    "b", False -> create_binary(tree, position)
    "t", False -> command(wrap_tuple(tree, position))
    "r", False -> wrap_row(tree, position)
    "e", False -> command(wrap_assignment(tree, position))
    "f", False -> command(wrap_function(tree, position))
    "p", False -> insert_provider(tree, position)
    "u", False -> command(unwrap(tree, position))
    // don't wrap in anything if modifies everything
    "c", False -> call(tree, position)
    "w", False -> call_with(tree, position)
    // m for match
    "m", False -> match(tree, position)

    "d", False -> delete(tree, position)
    // modes
    "i", False -> draft(tree, position)
    "v", False -> variable(tree, position)
    // sugar
    "n", False -> insert_named(tree, position)
    // xpand for view all in under selection
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
  let inner = path.append(position, 0)
  case get_element(tree, position) {
    Expression(#(_, e.Tuple([]))) -> {
      let new = ast.tuple_([ast.hole()])
      #(Some(replace_expression(tree, position, new)), inner, Command)
    }
    Expression(#(_, e.Row([]))) -> {
      let new = ast.row([#("", ast.hole())])
      #(
        Some(replace_expression(tree, position, new)),
        path.append(inner, 0),
        Draft(""),
      )
    }
    Expression(#(_, e.Binary(_))) | Expression(#(_, e.Variable(_))) -> #(
      None,
      position,
      Command,
    )
    Expression(_) -> #(None, inner, Command)
    RowField(_, _) -> #(None, inner, Command)
    Pattern(p.Tuple([]), _) -> #(
      Some(replace_pattern(tree, position, p.Tuple([None]))),
      inner,
      Draft(""),
    )
    Pattern(p.Row([]), _) -> #(
      Some(replace_pattern(tree, position, p.Row([#("", "")]))),
      path.append(inner, 0),
      Draft(""),
    )

    Pattern(p.Tuple(_), _) | Pattern(p.Row(_), _) | PatternField(_, _) -> #(
      None,
      inner,
      Command,
    )
    _ -> #(None, position, Command)
  }
}

fn pattern_left(pattern, selection) {
  case pattern, selection {
    _, [] -> None
    p.Tuple(elements), [i] -> {
      let left = i - 1
      case 0 <= left {
        True -> Some([left])
        False -> None
      }
    }
    p.Row(fields), [i] -> {
      let left = i - 1
      case 0 <= left {
        True -> Some([left])
        False -> None
      }
    }
    p.Row(fields), [i, 1] -> Some([i, 0])
    p.Row(fields), [i, 0] -> {
      let left = i - 1
      case 0 <= left {
        True -> Some([left, 1])
        False -> None
      }
    }
  }
}

fn do_move_left(tree, selection, position) {
  let #(_, expression) = tree
  // I think this is a get_expression
  // get expression doesn't work or parent tuple
  case expression, selection {
    // if single line move left, if multi line close
    e.Let(_, _, _), [1] -> position
    // poentianally move left right via the top of a function, but that plays weird with rows.
    e.Function(_, _), [1] -> path.append(position, 0)

    // might be best to check single line then can left out
    e.Let(pattern, _, _), [0, ..rest] | e.Function(pattern, _), [0, ..rest] ->
      case pattern_left(pattern, rest) {
        None -> list.append(position, selection)
        Some(inner) -> list.flatten([position, [0], inner])
      }
    e.Call(_, _), [1] | e.Provider(_, _, _), [1] -> path.append(position, 0)
    e.Tuple(elements), [i] ->
      case 0 <= i - 1 {
        True -> path.append(position, i - 1)
        False -> list.append(position, selection)
      }
    e.Row(fields), [i] ->
      case 0 <= i - 1 {
        True -> path.append(position, i - 1)
        False -> list.append(position, selection)
      }
    e.Row(fields), [i, 1] -> path.append(path.append(position, i), 0)
    e.Row(fields), [i, 0] ->
      case 0 <= i - 1 {
        True -> path.append(path.append(position, i - 1), 1)
        False -> list.append(position, selection)
      }
    // Step in
    _, [] -> position
    e.Tuple(elements), [i, ..rest] -> {
      assert Ok(element) = list.at(elements, i)
      do_move_left(element, rest, path.append(position, i))
    }
    e.Row(fields), [i, 1, ..rest] -> {
      assert Ok(#(_, value)) = list.at(fields, i)
      do_move_left(value, rest, path.append(path.append(position, i), 1))
    }
    e.Let(_, value, _), [1, ..rest] ->
      do_move_left(value, rest, path.append(position, 1))
    e.Let(_, _, then), [2, ..rest] ->
      do_move_left(then, rest, path.append(position, 2))
    e.Function(_, body), [1, ..rest] ->
      do_move_left(body, rest, path.append(position, 1))
    e.Call(func, _), [0, ..rest] ->
      do_move_left(func, rest, path.append(position, 0))
    e.Call(_, with), [1, ..rest] ->
      do_move_left(with, rest, path.append(position, 1))
  }
}

fn move_left(tree, position) {
  do_move_left(tree, position, [])
}

fn pattern_right(pattern, selection) {
  case pattern, selection {
    _, [] -> None
    p.Tuple(elements), [i] -> {
      let right = i + 1
      case right < list.length(elements) {
        True -> Some([right])
        False -> None
      }
    }
    p.Row(fields), [i] -> {
      let right = i + 1
      case right < list.length(fields) {
        True -> Some([right])
        False -> None
      }
    }
    p.Row(fields), [i, 0] -> Some([i, 1])
    p.Row(fields), [i, 1] -> {
      let right = i + 1
      case right < list.length(fields) {
        True -> Some([right, 0])
        False -> None
      }
    }
  }
}

fn do_move_right(tree, selection, position) {
  let #(_, expression) = tree
  // I think this is a get_expression
  // get expression doesn't work or parent tuple
  case expression, selection {
    e.Let(_, _, _), [] -> path.append(position, 1)
    e.Function(_, _), [] -> path.append(position, 1)

    // might be best to check single line then can left out
    e.Let(pattern, _, _), [0, ..rest] | e.Function(pattern, _), [0, ..rest] ->
      case pattern_right(pattern, rest) {
        None -> path.append(position, 1)
        Some(inner) -> list.flatten([position, [0], inner])
      }
    e.Call(_, _), [0] | e.Provider(_, _, _), [0] -> path.append(position, 1)
    e.Tuple(elements), [i] ->
      case i + 1 < list.length(elements) {
        True -> path.append(position, i + 1)
        False -> list.append(position, selection)
      }
    e.Row(fields), [i] ->
      case i + 1 < list.length(fields) {
        True -> path.append(position, i + 1)
        False -> list.append(position, selection)
      }
    e.Row(fields), [i, 0] -> path.append(path.append(position, i), 1)
    e.Row(fields), [i, 1] ->
      case i + 1 < list.length(fields) {
        True -> path.append(path.append(position, i + 1), 0)
        False -> list.append(position, selection)
      }
    // Step in
    _, [] -> position
    e.Tuple(elements), [i, ..rest] -> {
      assert Ok(element) = list.at(elements, i)
      do_move_right(element, rest, path.append(position, i))
    }
    e.Row(fields), [i, 1, ..rest] -> {
      assert Ok(#(_, value)) = list.at(fields, i)
      do_move_right(value, rest, path.append(path.append(position, i), 1))
    }
    e.Let(_, value, _), [1, ..rest] ->
      do_move_right(value, rest, path.append(position, 1))
    e.Let(_, _, then), [2, ..rest] ->
      do_move_right(then, rest, path.append(position, 2))
    e.Function(_, body), [1, ..rest] ->
      do_move_right(body, rest, path.append(position, 1))
    e.Call(func, _), [0, ..rest] ->
      do_move_right(func, rest, path.append(position, 0))
    e.Call(_, with), [1, ..rest] ->
      do_move_right(with, rest, path.append(position, 1))
  }
}

fn move_right(tree, position) {
  do_move_right(tree, position, [])
}

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

fn move_down(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) -> path.append(position, 2)

    _ ->
      case parent_let(tree, position) {
        None -> position
        Some(#(position, 0)) | Some(#(position, 1)) -> path.append(position, 2)
        Some(#(position, 2)) ->
          case block_container(tree, position) {
            // Select whole bottom line
            None -> path.append(position, 2)
            Some(position) -> move_down(tree, position)
          }
      }
  }
}

fn next_error(inconsistencies, path) {
  let points: List(List(Int)) =
    list.map(inconsistencies, fn(x: #(List(Int), String)) { x.0 })
  let next =
    list.find_by(
      points,
      fn(p) {
        case path.order(p, path) {
          order.Gt -> True
          _ -> False
        }
      },
    )
  case next {
    Ok(n) -> n
    Error(Nil) ->
      case points {
        [p, .._] -> p
        [] -> path
      }
  }
}

fn insert_at(items, cursor, new) {
  let pre = list.take(items, cursor)
  let post = list.drop(items, cursor)
  list.flatten([pre, [new], post])
}

// Considered doing nothing in the case that the target element was already blank
// Decided against to keep code simpler
fn space_left(tree, position) {
  insert_space(tree, position, 0)
}

fn space_right(tree, position) {
  insert_space(tree, position, 1)
}

fn insert_space(tree, position, offset) {
  case closest(tree, position, match_compound) {
    None -> #(None, position, Command)
    Some(#(position, cursor, TupleExpression(elements))) -> {
      let cursor = cursor + offset
      let new = ast.tuple_(insert_at(elements, cursor, ast.hole()))
      #(
        Some(replace_expression(tree, position, new)),
        path.append(position, cursor),
        Command,
      )
    }
    Some(#(position, cursor, RowExpression(fields))) -> {
      let cursor = cursor + offset
      let new = ast.row(insert_at(fields, cursor, #("", ast.hole())))
      #(
        Some(replace_expression(tree, position, new)),
        path.append(path.append(position, cursor), 0),
        Draft(""),
      )
    }
    Some(#(position, cursor, TuplePattern(elements))) -> {
      let cursor = cursor + offset
      let new = p.Tuple(insert_at(elements, cursor, None))
      #(
        Some(replace_pattern(tree, position, new)),
        path.append(position, cursor),
        Draft(""),
      )
    }
    Some(#(position, cursor, RowPattern(fields))) -> {
      let cursor = cursor + offset
      let new = p.Row(insert_at(fields, cursor, #("", "")))
      #(
        Some(replace_pattern(tree, position, new)),
        path.append(path.append(position, cursor), 0),
        Draft(""),
      )
    }
  }
}

fn space_below(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(pattern, value, then))) -> {
      let new =
        ast.let_(
          pattern,
          untype(value),
          ast.let_(p.Discard, ast.hole(), untype(then)),
        )
      #(
        replace_expression(tree, position, new),
        path.append(path.append(position, 2), 0),
      )
    }
    _ ->
      case closest(tree, position, match_let) {
        None -> #(ast.let_(p.Discard, untype(tree), ast.hole()), [2])
        Some(#(path, 2, #(pattern, value, then))) -> {
          let new =
            ast.let_(pattern, value, ast.let_(p.Discard, then, ast.hole()))
          #(
            replace_expression(tree, path, new),
            path.append(path.append(path, 2), 2),
          )
        }
        Some(#(path, _, #(pattern, value, then))) -> {
          let new =
            ast.let_(pattern, value, ast.let_(p.Discard, ast.hole(), then))
          #(
            replace_expression(tree, path, new),
            path.append(path.append(path, 2), 0),
          )
        }
      }
  }
}

fn space_above(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(pattern, value, then))) -> {
      let new =
        ast.let_(
          p.Discard,
          ast.hole(),
          ast.let_(pattern, untype(value), untype(then)),
        )
      #(replace_expression(tree, position, new), path.append(position, 0))
    }
    _ ->
      case closest(tree, position, match_let) {
        None -> #(ast.let_(p.Discard, ast.hole(), untype(tree)), [0])
        Some(#(path, 2, #(pattern, value, then))) -> {
          let new =
            ast.let_(pattern, value, ast.let_(p.Discard, ast.hole(), then))
          #(
            replace_expression(tree, path, new),
            path.append(path.append(path, 2), 0),
          )
        }
        Some(#(path, _, #(pattern, value, then))) -> {
          let new =
            ast.let_(p.Discard, ast.hole(), ast.let_(pattern, value, then))
          #(replace_expression(tree, path, new), path.append(path, 0))
        }
      }
  }
}

fn swap_pair(items, at) {
  let pre = list.take(items, at)
  let after = list.drop(items, at)
  case 0 <= at, after {
    True, [a, b, ..post] -> Ok(list.flatten([pre, [b, a], post]))
    _, _ -> Error(Nil)
  }
}

fn swap_elements(match, at) {
  case match {
    TupleExpression(elements) -> {
      try elements = swap_pair(elements, at)
      let e: List(e.Expression(Dynamic, Dynamic)) = elements
      Ok(Expression(ast.tuple_(elements)))
    }
    TuplePattern(elements) -> {
      try elements = swap_pair(elements, at)
      Ok(Pattern(p.Tuple(elements), todo("fix swap elements in patten")))
    }
    RowExpression(fields) -> {
      try fields = swap_pair(fields, at)
      Ok(Expression(ast.row(fields)))
    }
    RowPattern(fields) -> {
      try fields = swap_pair(fields, at)
      Ok(Pattern(p.Row(fields), todo("fix swap elements in patten")))
    }
  }
}

fn drag_left(tree, position) {
  case closest(tree, position, match_compound) {
    None -> #(untype(tree), position)
    Some(#(parent_position, cursor, match)) ->
      case swap_elements(match, cursor - 1) {
        Ok(Expression(new)) -> #(
          replace_expression(tree, parent_position, new),
          path.append(parent_position, cursor - 1),
        )
        Ok(Pattern(new, _)) -> #(
          replace_pattern(tree, parent_position, new),
          path.append(parent_position, cursor - 1),
        )
        Error(Nil) -> #(untype(tree), position)
      }
  }
}

fn drag_right(tree, position) {
  case closest(tree, position, match_compound) {
    None -> #(untype(tree), position)
    Some(#(parent_position, cursor, match)) ->
      case swap_elements(match, cursor) {
        Ok(Expression(new)) -> #(
          replace_expression(tree, parent_position, new),
          path.append(parent_position, cursor + 1),
        )
        Ok(Pattern(new, _)) -> #(
          replace_pattern(tree, parent_position, new),
          path.append(parent_position, cursor + 1),
        )
        Error(Nil) -> #(untype(tree), position)
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
        replace_expression(tree, path, new),
        path.append(path.append(path, 2), 0),
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
              #(
                replace_expression(tree, position, new),
                path.append(position, 0),
              )
            }
            _ -> #(untype(tree), original)
          }
      }
  }
}

type TupleMatch {
  TupleExpression(elements: List(e.Expression(Dynamic, Dynamic)))
  RowExpression(fields: List(#(String, e.Expression(Dynamic, Dynamic))))
  TuplePattern(elements: List(Option(String)))
  RowPattern(fields: List(#(String, String)))
}

// todo make untype_fields
fn match_compound(target) -> Result(TupleMatch, Nil) {
  case target {
    Expression(#(_, e.Tuple(elements))) ->
      Ok(TupleExpression(list.map(elements, untype)))
    Expression(#(_, e.Row(fields))) ->
      Ok(RowExpression(list.map(fields, untype_field)))
    Pattern(p.Tuple(elements), _) -> Ok(TuplePattern(elements))
    Pattern(p.Row(fields), _) -> Ok(RowPattern(fields))

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
  search: fn(Element(Metadata, #(Metadata, e.Node(Metadata, Dynamic)))) ->
    Result(t, Nil),
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

type Either(a, b) {
  Left(a)
  Right(b)
}

fn match_let_or_function(target) {
  case target {
    Expression(#(_, e.Let(p, v, t))) -> Ok(Left(#(p, untype(v), untype(t))))
    Expression(#(_, e.Function(p, b))) -> Ok(Right(#(p, untype(b))))
    _ -> Error(Nil)
  }
}

fn wrap_assignment(tree, position) {
  case closest(tree, position, match_let_or_function) {
    None -> #(ast.let_(p.Discard, untype(tree), ast.hole()), [0])
    // I don't support let in let yet
    Some(#(position, 2, Left(#(pattern, value, then)))) -> {
      let new = ast.let_(pattern, value, ast.let_(p.Discard, then, ast.hole()))
      #(
        replace_expression(tree, position, new),
        path.append(path.append(position, 2), 0),
      )
    }
    // Only need this case because we don't have dot access, but I use it for the boolean and list modules
    Some(#(position, 1, Left(#(pattern, value, then)))) -> {
      let new = ast.let_(pattern, ast.let_(p.Discard, value, ast.hole()), then)
      #(
        replace_expression(tree, position, new),
        path.append(path.append(position, 1), 0),
      )
    }
    Some(#(position, 1, Right(#(pattern, body)))) -> {
      let new = ast.function(pattern, ast.let_(p.Discard, body, ast.hole()))
      #(
        replace_expression(tree, position, new),
        path.append(path.append(position, 1), 0),
      )
    }
    _ -> #(untype(tree), position)
  }
}

fn create_binary(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Provider(_, e.Hole, _))) -> {
      let new = ast.binary("")
      #(Some(replace_expression(tree, position, new)), position, Draft(""))
    }
    _ -> #(None, position, Command)
  }
}

fn wrap_tuple(tree, position) {
  let target = get_element(tree, position)
  case target {
    Expression(#(_, e.Provider(_, e.Hole, _))) -> {
      let new = ast.tuple_([])
      #(replace_expression(tree, position, new), position)
    }
    Expression(expression) -> {
      let new = ast.tuple_([untype(expression)])
      #(replace_expression(tree, position, new), path.append(position, 0))
    }
    Pattern(p.Variable(label), _) -> #(
      replace_pattern(tree, position, p.Tuple([Some(label)])),
      path.append(position, 0),
    )
    Pattern(p.Discard, _) -> #(
      replace_pattern(tree, position, p.Tuple([])),
      position,
    )
    PatternElement(_, _) | Pattern(_, _) -> #(untype(tree), position)
  }
}

fn wrap_row(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Provider(_, e.Hole, _))) -> {
      let new = ast.row([])
      #(Some(replace_expression(tree, position, new)), position, Command)
    }
    Expression(expression) -> {
      let new = ast.row([#("", untype(expression))])
      #(
        Some(replace_expression(tree, position, new)),
        path.append(path.append(position, 0), 0),
        Draft(""),
      )
    }
    Pattern(p.Variable(label), _) -> #(
      Some(replace_pattern(tree, position, p.Row([#("", label)]))),
      path.append(path.append(position, 0), 0),
      Draft(""),
    )
    Pattern(p.Discard, _) -> #(
      Some(replace_pattern(tree, position, p.Row([]))),
      position,
      Command,
    )
    PatternElement(_, _) | Pattern(_, _) -> #(None, position, Command)
  }
}

fn wrap_function(tree, position) {
  case get_element(tree, position) {
    Expression(expression) -> {
      let new = ast.function(p.Discard, untype(expression))
      #(replace_expression(tree, position, new), path.append(position, 0))
    }
    _ -> #(untype(tree), position)
  }
}

fn insert_provider(tree, position) {
  let all_generators = list.map(e.all_generators(), e.generator_to_string)
  case get_element(tree, position) {
    Expression(#(_, expression)) -> {
      let new = case expression {
        e.Provider(config, generator, a) -> #(
          dynamic.from(Nil),
          e.Provider(config, generator, dynamic.from(Nil)),
        )
        _ -> ast.provider("", e.Loader)
      }
      #(
        Some(replace_expression(tree, position, new)),
        path.append(position, 0),
        Select(all_generators),
      )
    }
    ProviderGenerator(_) | ProviderConfig(_) -> {
      let Some(#(provider_position, _)) = parent_path(position)
      // assumed to be provider
      let Expression(#(_, e.Provider(_, _, _))) =
        get_element(tree, provider_position)
      #(None, path.append(provider_position, 0), Select(all_generators))
    }
    _ -> #(None, position, Command)
  }
}

// not very useful because we have to path all 3 elements out
// fn parent_element(tree, position) {
//   case parent_path(position) {
//     None -> None
//     Some(#(parent_position, index)) ->
//   }
//  }
fn unwrap(tree, position) {
  case parent_path(position) {
    None -> #(untype(tree), position)
    Some(#(parent_position, index)) -> {
      let parent = get_element(tree, parent_position)
      case parent, index {
        Expression(#(_, e.Tuple(elements))), _ -> {
          let [replacement, .._] = list.drop(elements, index)
          let modified =
            replace_expression(tree, parent_position, untype(replacement))
          #(modified, parent_position)
        }
        Expression(#(_, e.Row(fields))), _ -> {
          let [#(_, replacement), .._] = list.drop(fields, index)
          let modified =
            replace_expression(tree, parent_position, untype(replacement))
          #(modified, parent_position)
        }
        Expression(#(_, e.Call(func, _))), 0 -> {
          let modified = replace_expression(tree, parent_position, untype(func))
          #(modified, parent_position)
        }
        Expression(#(_, e.Call(_, with))), 1 -> {
          let modified = replace_expression(tree, parent_position, untype(with))
          #(modified, parent_position)
        }
        Expression(#(_, e.Let(_, value, _))), 1 -> {
          let modified =
            replace_expression(tree, parent_position, untype(value))
          #(modified, parent_position)
        }
        Expression(#(_, e.Function(_, body))), 1 -> {
          let modified = replace_expression(tree, parent_position, untype(body))
          #(modified, parent_position)
        }
        Expression(_), _ -> unwrap(tree, position)
        Pattern(p.Tuple(elements), _), _ -> {
          let [label, .._] = list.drop(elements, index)
          let pattern = case label {
            Some(label) -> p.Variable(label)
            None -> p.Discard
          }
          let modified = replace_pattern(tree, parent_position, pattern)
          #(modified, parent_position)
        }
      }
    }
  }
}

fn call(tree, position) {
  case get_element(tree, position) {
    // call a let is allowd here for foo
    // todo dot calling
    Expression(#(_, e.Let(_, _, _))) -> #(None, position, Command)
    Expression(expression) -> {
      let new = ast.call(untype(expression), ast.hole())
      let modified = replace_expression(tree, position, new)
      #(Some(modified), list.append(position, [1]), Command)
    }
    _ -> #(None, position, Command)
  }
}

fn call_with(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) -> #(None, position, Command)
    Expression(expression) -> {
      let new = ast.call(ast.hole(), untype(expression))
      let modified = replace_expression(tree, position, new)
      #(Some(modified), list.append(position, [0]), Command)
    }
    _ -> #(None, position, Command)
  }
}

fn match(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) -> #(None, position, Command)
    Expression(expression) -> {
      let new = ast.case_(untype(expression), [#("Foo", p.Discard, ast.hole())])
      let modified = replace_expression(tree, position, new)
      #(Some(modified), list.append(position, [0]), Command)
    }
    _ -> #(None, position, Command)
  }
}

fn delete(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, then))) -> #(
      Some(replace_expression(tree, position, untype(then))),
      position,
      Command,
    )
    Expression(#(_, e.Provider(_, e.Hole, _))) ->
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
                Some(replace_expression(tree, p_path, ast.tuple_(elements))),
                // TODO go to right path
                p_path,
                Command,
              )
            }
            RowField(_, _) -> {
              let Some(#(record_position, _)) = parent_path(p_path)
              let Expression(#(_, e.Row(fields))) =
                get_element(tree, record_position)
              let pre = list.take(fields, cursor)
              let post = list.drop(fields, cursor + 1)
              let fields =
                list.append(pre, post)
                |> list.map(untype_field)
              #(
                Some(replace_expression(tree, record_position, ast.row(fields))),
                p_path,
                Command,
              )
            }
            _ -> #(None, position, Command)
          }
        None -> #(None, position, Command)
      }
    Expression(_) -> #(
      Some(replace_expression(tree, position, ast.hole())),
      position,
      Command,
    )
    Pattern(_, _) -> #(
      Some(replace_pattern(tree, position, p.Discard)),
      position,
      Command,
    )
    PatternElement(cursor, el) -> {
      let Some(#(pattern_position, _)) = parent_path(position)
      let Pattern(p.Tuple(elements), _) = get_element(tree, pattern_position)
      // insert at can take a list
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
        _, True -> path.append(pattern_position, cursor - 1)
        _, False -> path.append(pattern_position, cursor)
      }
      #(
        Some(replace_pattern(tree, pattern_position, p.Tuple(elements))),
        position,
        Command,
      )
    }
    RowField(_, _) -> {
      let Some(#(row_position, cursor)) = parent_path(position)
      let Expression(#(_, e.Row(fields))) =
        get_element(tree, row_position)
        |> io.debug
      let pre = list.take(fields, cursor)
      let post = list.drop(fields, cursor + 1)
      let fields =
        list.append(pre, post)
        |> list.map(untype_field)
      #(
        Some(replace_expression(tree, row_position, ast.row(fields))),
        row_position,
        Command,
      )
    }
    RowKey(_, _) -> {
      let Some(#(field_position, cursor)) = parent_path(position)
      let Some(#(row_position, cursor)) = parent_path(field_position)
      let Expression(#(_, e.Row(fields))) = get_element(tree, row_position)
      let pre = list.take(fields, cursor)
      let post = list.drop(fields, cursor + 1)
      let fields =
        list.append(pre, post)
        |> list.map(untype_field)
      #(
        Some(replace_expression(tree, row_position, ast.row(fields))),
        row_position,
        Command,
      )
    }
    PatternField(_, _) -> {
      let Some(#(pattern_position, cursor)) = parent_path(position)
      let Pattern(p.Row(fields), _) = get_element(tree, pattern_position)
      let pre = list.take(fields, cursor)
      let post = list.drop(fields, cursor + 1)
      let fields = list.append(pre, post)
      #(
        Some(replace_pattern(tree, pattern_position, p.Row(fields))),
        pattern_position,
        Command,
      )
    }
    PatternKey(_, _) | PatternFieldBind(_, _) -> {
      let Some(#(field_position, _)) = parent_path(position)
      let Some(#(pattern_position, cursor)) = parent_path(field_position)
      let Pattern(p.Row(fields), _) = get_element(tree, pattern_position)
      let pre = list.take(fields, cursor)
      let post = list.drop(fields, cursor + 1)
      let fields = list.append(pre, post)
      #(
        Some(replace_pattern(tree, pattern_position, p.Row(fields))),
        pattern_position,
        Command,
      )
    }
  }
}

fn draft(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Binary(content))) -> #(None, position, Draft(content))
    Pattern(p.Discard, _) -> #(None, position, Draft(""))
    Pattern(p.Variable(label), _) -> #(None, position, Draft(label))
    PatternElement(_, None) -> #(None, position, Draft(""))
    PatternElement(_, Some(label)) -> #(None, position, Draft(label))
    RowKey(_, key) -> #(None, position, Draft(key))
    PatternKey(_, key) -> #(None, position, Draft(key))
    PatternFieldBind(_, label) -> #(None, position, Draft(label))
    ProviderConfig(config) -> #(None, position, Draft(config))
    _ -> #(None, position, Command)
  }
}

fn variable(tree, position) {
  case get_element(tree, position) {
    // Confusing to replace a whole Let at once.
    Expression(#(_, e.Let(_, _, _))) -> #(None, position, Command)
    Expression(#(metadata, _)) -> {
      let Metadata(scope: scope, ..) = metadata
      let variables =
        list.map(metadata.scope, fn(x: #(String, polytype.Polytype)) { x.0 })
      #(None, position, Select(variables))
    }
    _ -> #(None, position, Command)
  }
}

fn insert_named(tree, position) {
  case get_element(tree, position) {
    // Confusing to replace a whole Let at once.
    // maybe the value should only be a hole
    Expression(#(_, e.Let(p.Discard, _, then))) | Expression(#(
      _,
      e.Let(p.Variable(_), _, then),
    )) -> {
      let new =
        ast.let_(
          p.Variable("Foo"),
          ast.function(
            p.Row([#("Foo", "then")]),
            ast.call(ast.variable("then"), ast.tuple_([])),
          ),
          untype(then),
        )
      #(
        Some(replace_expression(tree, position, new)),
        path.append(position, 0),
        Draft("Foo"),
      )
    }
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
      replace_expression(tree, let_position, new)
    }
    Expression(#(_, e.Function(_, body))) -> {
      let new = ast.function(pattern, untype(body))
      replace_expression(tree, let_position, new)
    }
  }
}

fn parent_path(path) {
  case list.reverse(path) {
    [] -> None
    [last, ..rest] -> Some(#(list.reverse(rest), last))
  }
}

pub fn get_element(tree: e.Expression(a, b), position) -> Element(a, b) {
  case tree, position {
    _, [] -> Expression(tree)
    #(_, e.Tuple(elements)), [i, ..rest] -> {
      let [child, .._] = list.drop(elements, i)
      get_element(child, rest)
    }
    #(_, e.Row(fields)), [i] -> {
      let [field, .._] = list.drop(fields, i)
      RowField(i, field)
    }
    #(_, e.Row(fields)), [i, 0] -> {
      let [#(key, _), .._] = list.drop(fields, i)
      RowKey(i, key)
    }
    #(_, e.Row(fields)), [i, 1, ..rest] -> {
      let [#(_, child), .._] = list.drop(fields, i)
      get_element(child, rest)
    }
    #(_, e.Let(pattern, _, _)), [0] -> Pattern(pattern, tree)
    #(_, e.Let(p.Tuple(elements), _, _)), [0, i] -> {
      // l.at and this should be an error instead
      let [element, .._] = list.drop(elements, i)
      PatternElement(i, element)
    }
    #(_, e.Let(p.Row(fields), _, _)), [0, i] -> {
      // l.at and this should be an error instead
      let [field, .._] = list.drop(fields, i)
      PatternField(i, field)
    }
    #(_, e.Let(p.Row(fields), _, _)), [0, i, 0] -> {
      // l.at and this should be an error instead
      let [#(key, _), .._] = list.drop(fields, i)
      PatternKey(i, key)
    }
    #(_, e.Let(p.Row(fields), _, _)), [0, i, 1] -> {
      // l.at and this should be an error instead
      let [#(_, bind), .._] = list.drop(fields, i)
      PatternFieldBind(i, bind)
    }
    #(_, e.Let(_, value, _)), [1, ..rest] -> get_element(value, rest)
    #(_, e.Let(_, _, then)), [2, ..rest] -> get_element(then, rest)
    #(_, e.Function(pattern, _)), [0] -> Pattern(pattern, tree)
    #(_, e.Function(p.Tuple(elements), _)), [0, i] -> {
      // l.at and this should be an error instead
      let [element, .._] = list.drop(elements, i)
      PatternElement(i, element)
    }
    #(_, e.Function(p.Row(fields), _)), [0, i] -> {
      // l.at and this should be an error instead
      let [field, .._] = list.drop(fields, i)
      PatternField(i, field)
    }
    #(_, e.Function(p.Row(fields), _)), [0, i, 0] -> {
      // l.at and this should be an error instead
      let [#(key, _), .._] = list.drop(fields, i)
      PatternKey(i, key)
    }
    #(_, e.Function(p.Row(fields), _)), [0, i, 1] -> {
      // l.at and this should be an error instead
      let [#(_, bind), .._] = list.drop(fields, i)
      PatternFieldBind(i, bind)
    }
    #(_, e.Function(_, body)), [1, ..rest] -> get_element(body, rest)
    #(_, e.Call(func, _)), [0, ..rest] -> get_element(func, rest)
    #(_, e.Call(_, with)), [1, ..rest] -> get_element(with, rest)
    #(_, e.Case(value, _)), [0, ..rest] -> get_element(value, rest)
    #(_, e.Provider(_, generator, _)), [0] -> ProviderGenerator(generator)
    #(_, e.Provider(config, _, _)), [1] -> ProviderConfig(config)
  }
}

pub fn replace_expression(
  tree: e.Expression(a, b),
  path: List(Int),
  replacement: e.Expression(Dynamic, Dynamic),
) -> e.Expression(Dynamic, Dynamic) {
  let tree = untype(tree)
  map_node(tree, path, fn(_) { replacement })
}

pub fn map_node(
  tree: e.Expression(a, b),
  path: List(Int),
  mapper: fn(e.Expression(a, b)) -> e.Expression(Dynamic, Dynamic),
) -> e.Expression(Dynamic, Dynamic) {
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
    e.Row(fields), [index, 1, ..rest] -> {
      let pre =
        list.take(fields, index)
        |> list.map(untype_field)
      let [#(k, current), ..post] = list.drop(fields, index)
      let post = list.map(post, untype_field)
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
    e.Case(value, branches), [0, ..rest] -> {
      let branches =
        list.map(
          branches,
          fn(branch) {
            let #(name, pattern, then) = branch
            #(name, pattern, untype(then))
          },
        )
      ast.case_(map_node(value, rest, mapper), branches)
    }
  }
}
