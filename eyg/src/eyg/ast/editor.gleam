import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/order
import gleam/pair
import gleam/string
import eyg
import eyg/ast
import eyg/ast/encode
import eyg/ast/path
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer.{Metadata}
import eyg/typer/monotype as t
import eyg/typer/polytype
import eyg/typer/harness
import eyg/codegen/javascript

pub type Mode {
  Command
  Draft(content: String)
  Select(choices: List(String))
}

pub type Editor(n) {
  Editor(
    harness: harness.Harness(n),
    // maybe manipulate only untyped as tree, call it source??
    tree: e.Expression(Metadata(n), e.Expression(Metadata(n), Dynamic)),
    typer: typer.Typer(n),
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

fn expression_type(
  expression: e.Expression(Metadata(n), a),
  typer: typer.Typer(n),
  native_to_string,
) {
  let #(metadata, _) = expression
  case metadata.type_ {
    Ok(t) -> #(
      False,
      t.resolve(t, typer.substitutions)
      |> t.to_string(native_to_string),
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
        Expression(#(_, e.Let(_, value, _))) ->
          expression_type(value, typer, editor.harness.native_to_string)
        Expression(expression) ->
          expression_type(expression, typer, editor.harness.native_to_string)
        _ -> #(False, "")
      }
    None -> #(False, "")
  }
}

pub fn is_selected(editor: Editor(n), path) {
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
  |> list.map(fn(i) {
    let #(path, reason) = i
    #(path, typer.reason_to_string(reason, t))
  })
}

// reuse this code by putting it in platform.compile/codegen/eval
// Question does editor depend on platform or visaverca happy to make descision later
pub fn codegen(editor) {
  let Editor(tree: tree, typer: typer, ..) = editor
  let good = list.length(typer.inconsistencies) == 0
  let code =
    javascript.render_to_string(tree, typer, editor.harness.native_to_string)
  #(good, code)
}

pub fn eval(editor) {
  let Editor(tree: tree, typer: typer, ..) = editor
  assert True = list.length(typer.inconsistencies) == 0
  javascript.eval(tree, typer, editor.harness.native_to_string)
}

pub fn dump(editor) {
  let Editor(tree: tree, ..) = editor
  let dump =
    encode.to_json(tree)
    |> encode.json_to_string
  dump
}

pub fn init(source, harness) {
  let untyped = encode.from_json(encode.json_from_string(source))
  let #(typed, typer) = eyg.compile_unconstrained(untyped, harness)
  Editor(harness, typed, typer, None, Command, False)
}

fn rest_to_path(rest) {
  case rest {
    "" -> Ok([])
    _ ->
      // empty string makes unparsable as int list
      string.split(rest, ",")
      |> list.try_map(int.parse)
  }
}

// At the editor level we might want to handle semantic events like select node. And have display do handle click
pub fn handle_click(editor: Editor(n), target) {
  case string.split(target, ":") {
    ["root"] -> Editor(..editor, selection: Some([]), mode: Command)
    ["p", rest] -> {
      assert Ok(path) = rest_to_path(rest)
      Editor(..editor, selection: Some(path), mode: Command)
    }
  }
}

pub fn handle_keydown(editor, key, ctrl_key) {
  let Editor(tree: tree, typer: typer, selection: selection, mode: mode, ..) =
    editor
  assert Some(path) = selection
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
            Some(untyped) -> eyg.compile_unconstrained(untyped, editor.harness)
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
    Select(_) if key == "Escape" -> Editor(..editor, mode: Command)
    _ -> todo("any oether keydown should not happen")
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

fn handle_expression_change(expression, content) {
  let #(_, tree) = untype(expression)
  case tree {
    e.Binary(_) -> ast.binary(content)
    e.Tagged(_, value) -> e.tagged(content, value)
    _ -> ast.variable(content)
  }
}

pub fn handle_change(editor, content) {
  let Editor(tree: tree, selection: selection, ..) = editor
  assert Some(position) = selection
  let untyped = case get_element(tree, position) {
    Expression(e) -> {
      let new = handle_expression_change(e, content)
      replace_expression(tree, position, new)
    }
    Pattern(p.Variable(_), _) ->
      replace_pattern(tree, position, p.Variable(content))
    // Putting stuff in the pattern Element works
    PatternElement(i, _) -> {
      assert Ok(#(pattern_position, _)) = path.parent(position)
      assert Pattern(p.Tuple(elements), _) = get_element(tree, pattern_position)
      let pre = list.take(elements, i)
      let [_, ..post] = list.drop(elements, i)
      let elements = list.flatten([pre, [content], post])
      replace_pattern(tree, pattern_position, p.Tuple(elements))
    }
    RowKey(i, _) -> {
      assert Ok(#(field_position, _)) = path.parent(position)
      assert Ok(#(record_position, _)) = path.parent(field_position)
      assert Expression(#(_, e.Record(fields))) =
        get_element(tree, record_position)
      let pre =
        list.take(fields, i)
        |> list.map(untype_field)
      let [#(_, value), ..post] = list.drop(fields, i)
      let post =
        post
        |> list.map(untype_field)
      let fields = list.flatten([pre, [#(content, untype(value))], post])
      replace_expression(tree, record_position, e.record(fields))
    }
    PatternKey(i, _) -> {
      assert Ok(#(field_position, _)) = path.parent(position)
      assert Ok(#(pattern_position, _)) = path.parent(field_position)
      assert Pattern(p.Record(fields), _) = get_element(tree, pattern_position)
      // TODO map at
      let pre = list.take(fields, i)
      let [#(_, label), ..post] = list.drop(fields, i)
      let fields = list.flatten([pre, [#(content, label)], post])
      replace_pattern(tree, pattern_position, p.Record(fields))
    }
    PatternFieldBind(i, _) -> {
      assert Ok(#(field_position, _)) = path.parent(position)
      assert Ok(#(pattern_position, _)) = path.parent(field_position)
      assert Pattern(p.Record(fields), _) = get_element(tree, pattern_position)
      // TODO map at
      let pre = list.take(fields, i)
      let [#(key, _), ..post] = list.drop(fields, i)
      let fields = list.flatten([pre, [#(key, content)], post])
      replace_pattern(tree, pattern_position, p.Record(fields))
    }
    ProviderGenerator(_) -> {
      assert Ok(#(provider_position, _)) = path.parent(position)
      assert Expression(#(_, e.Provider(config, _, _))) =
        get_element(tree, provider_position)
      let new = ast.provider(config, e.generator_from_string(content))
      replace_expression(tree, provider_position, new)
    }
    ProviderConfig(_) -> {
      assert Ok(#(provider_position, _)) = path.parent(position)
      assert Expression(#(_, e.Provider(_, generator, _))) =
        get_element(tree, provider_position)
      let new = ast.provider(content, generator)
      replace_expression(tree, provider_position, new)
    }

    BranchName(_) -> {
      assert Ok(#(branch_position, _)) = path.parent(position)
      assert Ok(#(case_position, i)) = path.parent(branch_position)
      assert Expression(#(_, e.Case(value, branches))) =
        get_element(tree, case_position)
      let pre = list.take(branches, i - 1)
      let [branch, ..post] = list.drop(branches, i - 1)
      let #(_, pattern, then) = branch
      let branch = #(content, pattern, then)
      let branches =
        list.flatten([pre, [branch], post])
        |> list.map(untype_branch)
      let new = ast.case_(untype(value), branches)
      replace_expression(tree, case_position, new)
    }
    _ -> todo("handle the other options")
  }

  let #(typed, typer) = eyg.compile_unconstrained(untyped, editor.harness)
  Editor(..editor, tree: typed, typer: typer, mode: Command)
}

pub type Element(a, b) {
  Expression(e.Expression(a, b))
  RowField(Int, #(String, e.Expression(a, b)))
  RowKey(Int, String)
  Tag(String)
  Pattern(p.Pattern, e.Expression(a, b))
  PatternElement(Int, String)
  PatternField(Int, #(String, String))
  PatternKey(Int, String)
  PatternFieldBind(Int, String)
  Branch(Int)
  BranchName(String)
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

pub fn untype_branch(
  field: #(String, p.Pattern, e.Expression(a, b)),
) -> #(String, p.Pattern, e.Expression(Dynamic, Dynamic)) {
  let #(label, pattern, value) = field
  #(label, pattern, untype(value))
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
    "r", False -> wrap_record(tree, position)
    "n", False -> wrap_tagged(tree, position)
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
    // xpand for view all in under selection
    // Fallback
    "Control", _ | "Shift", _ | "Alt", _ | "Meta", _ -> #(
      None,
      position,
      Command,
    )
    _, _ -> {
      io.debug(string.concat(["No edit action for key: ", key]))
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

fn increase_selection(_tree, position) {
  case path.parent(position) {
    Ok(#(position, _)) -> position
    Error(Nil) -> []
  }
}

fn decrease_selection(tree, position) {
  let inner = path.append(position, 0)
  case get_element(tree, position) {
    Expression(#(_, e.Tuple([]))) -> {
      let new = ast.tuple_([ast.hole()])
      #(Some(replace_expression(tree, position, new)), inner, Command)
    }
    Expression(#(_, e.Record([]))) -> {
      let new = e.record([#("", ast.hole())])
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
      Some(replace_pattern(tree, position, p.Tuple([""]))),
      inner,
      Draft(""),
    )
    Pattern(p.Record([]), _) -> #(
      Some(replace_pattern(tree, position, p.Record([#("", "")]))),
      path.append(inner, 0),
      Draft(""),
    )

    Pattern(p.Tuple(_), _) | Pattern(p.Record(_), _) | PatternField(_, _) -> #(
      None,
      inner,
      Command,
    )
    Branch(_) -> #(None, inner, Command)
    _ -> #(None, position, Command)
  }
}

fn pattern_left(pattern, selection) {
  case pattern, selection {
    _, [] -> None
    p.Tuple(_elements), [i] -> {
      let left = i - 1
      case 0 <= left {
        True -> Some([left])
        False -> None
      }
    }
    p.Record(_fields), [i] -> {
      let left = i - 1
      case 0 <= left {
        True -> Some([left])
        False -> None
      }
    }
    p.Record(_fields), [i, 1] -> Some([i, 0])
    p.Record(_fields), [i, 0] -> {
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
    // poentianally move left right via the top of a function, but that plays weird with records.
    e.Function(_, _), [1] -> path.append(position, 0)

    // might be best to check single line then can left out
    e.Let(pattern, _, _), [0, ..rest] | e.Function(pattern, _), [0, ..rest] ->
      case pattern_left(pattern, rest) {
        None -> list.append(position, selection)
        Some(inner) -> list.flatten([position, [0], inner])
      }
    e.Call(_, _), [1] | e.Provider(_, _, _), [1] -> path.append(position, 0)
    e.Tuple(_elements), [i] ->
      case 0 <= i - 1 {
        True -> path.append(position, i - 1)
        False -> list.append(position, selection)
      }
    e.Record(_fields), [i] ->
      case 0 <= i - 1 {
        True -> path.append(position, i - 1)
        False -> list.append(position, selection)
      }
    e.Record(_fields), [i, 1] -> path.append(path.append(position, i), 0)
    e.Record(_fields), [i, 0] ->
      case 0 <= i - 1 {
        True -> path.append(path.append(position, i - 1), 1)
        False -> list.append(position, selection)
      }
    e.Tagged(_, _), [1] -> path.append(position, 0)
    // Step in
    _, [] -> position
    e.Tuple(elements), [i, ..rest] -> {
      assert Ok(element) = list.at(elements, i)
      do_move_left(element, rest, path.append(position, i))
    }
    e.Record(fields), [i, 1, ..rest] -> {
      assert Ok(#(_, value)) = list.at(fields, i)
      do_move_left(value, rest, path.append(path.append(position, i), 1))
    }
    e.Tagged(_, value), [1, ..rest] ->
      do_move_left(value, rest, path.append(position, 1))
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
    // move within value
    e.Case(value, _), [0, ..rest] ->
      do_move_left(value, rest, path.append(position, 0))
    // move along branch elements
    e.Case(_, _), [i, j] if i > 0 && j > 0 ->
      path.append(path.append(position, i), j - 1)
    e.Case(_, branches), [i, 1, ..rest] -> {
      assert Ok(#(_, pattern, _)) = list.at(branches, i - 1)
      case pattern_left(pattern, rest) {
        None -> list.append(position, [i, 0])
        Some(inner) -> list.flatten([position, [i, 1], inner])
      }
    }
    // do_move_left(then, rest, path.append(path.append(position, i), 1))
    e.Case(_, branches), [i, 2, ..rest] -> {
      assert Ok(#(_, _, then)) = list.at(branches, i - 1)
      do_move_left(then, rest, path.append(path.append(position, i), 2))
    }
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
    p.Record(fields), [i] -> {
      let right = i + 1
      case right < list.length(fields) {
        True -> Some([right])
        False -> None
      }
    }
    p.Record(_fields), [i, 0] -> Some([i, 1])
    p.Record(fields), [i, 1] -> {
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
    e.Record(fields), [i] ->
      case i + 1 < list.length(fields) {
        True -> path.append(position, i + 1)
        False -> list.append(position, selection)
      }
    e.Record(_fields), [i, 0] -> path.append(path.append(position, i), 1)
    e.Record(fields), [i, 1] ->
      case i + 1 < list.length(fields) {
        True -> path.append(path.append(position, i + 1), 0)
        False -> list.append(position, selection)
      }
    e.Tagged(_, _), [0] -> path.append(position, 1)
    e.Case(_, _), [0] | e.Case(_, _), [] -> path.append(position, 1)
    // Step in
    _, [] -> position
    e.Tuple(elements), [i, ..rest] -> {
      assert Ok(element) = list.at(elements, i)
      do_move_right(element, rest, path.append(position, i))
    }
    e.Record(fields), [i, 1, ..rest] -> {
      assert Ok(#(_, value)) = list.at(fields, i)
      do_move_right(value, rest, path.append(path.append(position, i), 1))
    }
    e.Tagged(_, value), [1, ..rest] ->
      do_move_right(value, rest, path.append(position, 1))
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
    e.Case(value, _), [0, ..rest] ->
      do_move_right(value, rest, path.append(position, 0))
    e.Case(_, _), [i, j] if i > 0 && j < 2 ->
      path.append(path.append(position, i), j + 1)
    e.Case(_, branches), [i, 1, ..rest] -> {
      assert Ok(#(_, pattern, _)) = list.at(branches, i - 1)
      case pattern_right(pattern, rest) {
        None -> list.append(position, [i, 2])
        Some(inner) -> list.flatten([position, [i, 1], inner])
      }
    }
    e.Case(_, branches), [i, 2, ..rest] -> {
      assert Ok(#(_, _, then)) = list.at(branches, i - 1)
      do_move_right(then, rest, path.append(path.append(position, i), 2))
    }
  }
}

fn move_right(tree, position) {
  do_move_right(tree, position, [])
}

fn match_let_or_case(target) {
  case target {
    Expression(#(_, e.Let(p, v, t))) -> Ok(Left(#(p, untype(v), untype(t))))
    Expression(#(_, e.Case(v, bs))) ->
      Ok(Right(#(v, list.map(bs, untype_branch))))
    _ -> Error(Nil)
  }
}

fn move_up(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) ->
      case path.parent(position) {
        Ok(#(p, _)) -> p
        Error(Nil) -> position
      }
    Expression(#(_, e.Case(_, _))) ->
      case path.parent(position) {
        Ok(#(p, _)) -> move_up(tree, p)
        Error(Nil) -> position
      }
    _ ->
      case closest(tree, position, match_let_or_case) {
        None -> position
        Some(#(p, 0, Left(_))) | Some(#(p, 1, Left(_))) ->
          case path.parent(p) {
            Ok(#(p, _)) -> p
            Error(Nil) -> p
          }
        Some(#(p, 2, Left(_))) -> p
        // On the top line of a case
        Some(#(p, 0, Right(_))) -> move_up(tree, p)
        Some(#(p, i, Right(_))) -> path.append(p, i - 1)
      }
  }
}

fn move_down(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) -> path.append(position, 2)

    _ ->
      case closest(tree, position, match_let_or_case) {
        None -> position
        Some(#(position, 0, Left(_))) | Some(#(position, 1, Left(_))) ->
          path.append(position, 2)
        Some(#(position, 2, Left(_))) ->
          case block_container(tree, position) {
            // Select whole bottom line
            None -> path.append(position, 2)
            Some(position) -> move_down(tree, position)
          }
        Some(#(position, i, Right(#(_value, branches)))) ->
          case i < list.length(branches) {
            True -> path.append(position, i + 1)
            False -> move_down(tree, position)
          }
      }
  }
}

// make a next point function in ast
fn next_error(inconsistencies, path) {
  let points: List(List(Int)) = list.map(inconsistencies, pair.first)
  let next =
    list.find(
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
        [p, ..] -> p
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
      let new = e.record(insert_at(fields, cursor, #("", ast.hole())))
      #(
        Some(replace_expression(tree, position, new)),
        path.append(path.append(position, cursor), 0),
        Draft(""),
      )
    }
    Some(#(position, cursor, TuplePattern(elements))) -> {
      let cursor = cursor + offset
      let new = p.Tuple(insert_at(elements, cursor, ""))
      #(
        Some(replace_pattern(tree, position, new)),
        path.append(position, cursor),
        Draft(""),
      )
    }
    Some(#(position, cursor, RowPattern(fields))) -> {
      let cursor = cursor + offset
      let new = p.Record(insert_at(fields, cursor, #("", "")))
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
          ast.let_(p.Variable(""), ast.hole(), untype(then)),
        )
      #(
        replace_expression(tree, position, new),
        path.append(path.append(position, 2), 0),
      )
    }
    _ ->
      case closest(tree, position, match_let) {
        None -> #(ast.let_(p.Variable(""), untype(tree), ast.hole()), [2])
        Some(#(path, 2, #(pattern, value, then))) -> {
          let new =
            ast.let_(pattern, value, ast.let_(p.Variable(""), then, ast.hole()))
          #(
            replace_expression(tree, path, new),
            path.append(path.append(path, 2), 2),
          )
        }
        Some(#(path, _, #(pattern, value, then))) -> {
          let new =
            ast.let_(pattern, value, ast.let_(p.Variable(""), ast.hole(), then))
          #(
            replace_expression(tree, path, new),
            path.append(path.append(path, 2), 0),
          )
        }
      }
  }
}

type BlockLine(m, n) {
  Let(pattern: p.Pattern, value: e.Expression(m, n), then: e.Expression(m, n))
  CaseBranch
}

fn block_line(element) {
  case element {
    Expression(#(_, e.Let(p, v, t))) -> Ok(Let(p, v, t))
    Branch(_) -> Ok(CaseBranch)
    _ -> Error(Nil)
  }
}

fn do_from_here(tree, path, search, inner) {
  case search(get_element(tree, path)) {
    Ok(match) -> Ok(#(match, path, inner))
    Error(Nil) ->
      case path.parent(path) {
        Ok(#(path, i)) -> do_from_here(tree, path, search, [i, ..inner])
        Error(Nil) -> Error(Nil)
      }
  }
}

fn from_here(tree, path, search) {
  do_from_here(tree, path, search, [])
}

// If in a block must be on a in a let
fn space_above(tree, path) {
  let tree = untype(tree)
  case from_here(tree, path, block_line) {
    Error(Nil) -> {
      let updated = ast.let_(p.Variable(""), ast.hole(), tree)
      let path = [0]
      #(updated, path)
    }
    Ok(#(Let(p, v, t), path, [2, ..])) -> {
      let new = ast.let_(p, v, ast.let_(p.Variable(""), ast.hole(), t))
      let updated = replace_expression(tree, path, new)
      let path = list.append(path, [2, 0])
      #(updated, path)
    }
    Ok(#(Let(p, v, t), path, _)) -> {
      let new = ast.let_(p.Variable(""), ast.hole(), ast.let_(p, v, t))
      let updated = replace_expression(tree, path, new)
      let path = list.append(path, [0])
      #(updated, path)
    }
    Ok(#(CaseBranch, path, _)) -> {
      assert Ok(#(path, i)) = path.parent(path)
      assert Expression(#(_, e.Case(value, branches))) = get_element(tree, path)
      let bi = i - 1
      let pre = list.take(branches, bi)
      let post = list.drop(branches, bi)
      let new = #("Variant", p.Variable(""), ast.hole())
      let branches = list.flatten([pre, [new], post])
      let new = ast.case_(value, branches)
      let updated = replace_expression(tree, path, new)
      let path = list.append(path, [bi + 1, 0])
      #(updated, path)
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
      Ok(Expression(ast.tuple_(elements)))
    }
    TuplePattern(elements) -> {
      try elements = swap_pair(elements, at)
      // This hole is not used we are reusing the Pattern type which expects a parent expression
      Ok(Pattern(p.Tuple(elements), ast.hole()))
    }
    RowExpression(fields) -> {
      try fields = swap_pair(fields, at)
      Ok(Expression(e.record(fields)))
    }
    RowPattern(fields) -> {
      try fields = swap_pair(fields, at)
      // This hole is not used we are reusing the Pattern type which expects a parent expression
      Ok(Pattern(p.Record(fields), ast.hole()))
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
    // leave as is, can't drag past un assigned
    Some(#(_path, 2, _)) -> #(untype(tree), position)
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
    // leave as is, would meet a 0/1 node first if dragable.
    Some(#(_position, 2, _)) -> #(untype(tree), original)
    Some(#(position, _, #(pattern, value, then))) ->
      case path.parent(position) {
        Error(Nil) -> #(untype(tree), original)
        Ok(#(position, _)) ->
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
  TuplePattern(elements: List(String))
  RowPattern(fields: List(#(String, String)))
}

fn match_compound(target) -> Result(TupleMatch, Nil) {
  case target {
    Expression(#(_, e.Tuple(elements))) ->
      Ok(TupleExpression(list.map(elements, untype)))
    Expression(#(_, e.Record(fields))) ->
      Ok(RowExpression(list.map(fields, untype_field)))
    Pattern(p.Tuple(elements), _) -> Ok(TuplePattern(elements))
    Pattern(p.Record(fields), _) -> Ok(RowPattern(fields))

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
  search: fn(Element(Metadata(n), #(Metadata(n), e.Node(Metadata(n), Dynamic)))) ->
    Result(t, Nil),
) -> Option(#(List(Int), Int, t)) {
  case path.parent(position) {
    Error(Nil) -> None
    Ok(#(position, index)) ->
      case search(get_element(tree, position)) {
        Ok(x) -> Some(#(position, index, x))
        Error(_) -> closest(tree, position, search)
      }
  }
}

fn block_container(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Let(_, _, _))) ->
      case path.parent(position) {
        Error(Nil) -> None
        Ok(#(position, _)) -> block_container(tree, position)
      }
    Expression(_) -> Some(position)
    _ -> todo("so many other options")
  }
}

type Either(a, b) {
  Left(a)
  Right(b)
}

fn current_expression(tree, position, inner) {
  case get_element(tree, position) {
    Expression(e) -> #(e, position, inner)
    _ -> {
      assert Ok(#(path, p)) = path.parent(position)
      current_expression(tree, path, [p, ..inner])
    }
  }
}

fn wrap_assignment(tree, path) {
  let #(expression, path, _inner) = current_expression(untype(tree), path, [])
  // Inner must always be pointing to the pattern or the let node itself.
  let new = case expression {
    #(_, e.Let(p, v, t)) ->
      ast.let_(p.Variable(""), ast.let_(p, v, ast.hole()), t)
    _ -> ast.let_(p.Variable(""), expression, ast.hole())
  }
  let updated = replace_expression(tree, path, new)
  #(updated, path.append(path, 0))
}

fn create_binary(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Hole)) -> {
      let new = ast.binary("")
      #(Some(replace_expression(tree, position, new)), position, Draft(""))
    }
    _ -> #(None, position, Command)
  }
}

fn wrap_tuple(tree, position) {
  let target = get_element(tree, position)
  case target {
    Expression(#(_, e.Hole)) -> {
      let new = ast.tuple_([])
      #(replace_expression(tree, position, new), position)
    }
    Expression(expression) -> {
      let new = ast.tuple_([untype(expression)])
      #(replace_expression(tree, position, new), path.append(position, 0))
    }
    Pattern(p.Variable(""), _) -> #(
      replace_pattern(tree, position, p.Tuple([])),
      position,
    )
    Pattern(p.Variable(label), _) -> #(
      replace_pattern(tree, position, p.Tuple([label])),
      path.append(position, 0),
    )
    PatternElement(_, _) | Pattern(_, _) -> #(untype(tree), position)
    _ -> todo("more tuple wrapping possibilities")
  }
}

fn wrap_record(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, e.Hole)) -> {
      let new = e.record([])
      #(Some(replace_expression(tree, position, new)), position, Command)
    }
    Expression(expression) -> {
      let new = e.record([#("", untype(expression))])
      #(
        Some(replace_expression(tree, position, new)),
        path.append(path.append(position, 0), 0),
        Draft(""),
      )
    }
    Pattern(p.Variable(""), _) -> #(
      Some(replace_pattern(tree, position, p.Record([]))),
      position,
      Command,
    )
    Pattern(p.Variable(label), _) -> #(
      Some(replace_pattern(tree, position, p.Record([#("", label)]))),
      path.append(path.append(position, 0), 0),
      Draft(""),
    )
    PatternElement(_, _) | Pattern(_, _) -> #(None, position, Command)
    _ -> todo("cant wrap as record")
  }
}

fn wrap_tagged(tree, path) {
  case get_element(tree, path) {
    Expression(#(_, e.Let(_, value, _))) ->
      wrap_tagged(tree, path.append(path, 1))
    Expression(e) -> {
      let inner = path.append(path, 0)
      let new = e.tagged("", untype(e))
      #(Some(replace_expression(tree, path, new)), path, Draft(""))
    }
    _ -> #(None, path, Command)
  }
}

fn wrap_function(tree, position) {
  case get_element(tree, position) {
    Expression(expression) -> {
      let new = ast.function(p.Variable(""), untype(expression))
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
        e.Provider(config, generator, _) -> #(
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
      assert Ok(#(provider_position, _)) = path.parent(position)
      // assumed to be provider
      assert Expression(#(_, e.Provider(_, _, _))) =
        get_element(tree, provider_position)
      #(None, path.append(provider_position, 0), Select(all_generators))
    }
    _ -> #(None, position, Command)
  }
}

fn unwrap(tree, position) {
  case path.parent(position) {
    Error(Nil) -> #(untype(tree), position)
    Ok(#(parent_position, index)) -> {
      let parent = get_element(tree, parent_position)
      case parent, index {
        Expression(#(_, e.Tuple(elements))), _ -> {
          let [replacement, ..] = list.drop(elements, index)
          let modified =
            replace_expression(tree, parent_position, untype(replacement))
          #(modified, parent_position)
        }
        Expression(#(_, e.Record(fields))), _ -> {
          let [#(_, replacement), ..] = list.drop(fields, index)
          let modified =
            replace_expression(tree, parent_position, untype(replacement))
          #(modified, parent_position)
        }
        Expression(#(_, e.Tagged(_, value))), _ -> {
          let modified =
            replace_expression(tree, parent_position, untype(value))
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
        Expression(#(_, e.Case(value, _))), 0 -> {
          let modified =
            replace_expression(tree, parent_position, untype(value))
          #(modified, parent_position)
        }
        Pattern(p.Tuple(elements), _), _ -> {
          let [label, ..] = list.drop(elements, index)
          let pattern = p.Variable(label)
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
      let new =
        ast.case_(
          untype(expression),
          [#("Variant", p.Variable(""), ast.hole())],
        )
      let modified = replace_expression(tree, position, new)
      #(Some(modified), list.append(position, [1, 0]), Draft(""))
    }
    _ -> #(None, position, Command)
  }
}

fn delete(tree, position) {
  assert Some(#(tree, position)) = do_delete(untype(tree), position)
  #(Some(tree), position, Command)
}

fn max(a, b) {
  case a < b {
    True -> b
    False -> a
  }
}

// Map node with step out? left right and delete
fn do_delete(tree, position) {
  let #(_, expression) = tree
  case expression, position {
    e.Hole, [] -> None
    e.Let(_, _, then), [] -> Some(#(then, position))
    _, [] -> Some(#(ast.hole(), position))
    e.Tuple(elements), [i, ..rest] -> {
      let pre = list.take(elements, i)
      let [inner, ..post] = list.drop(elements, i)
      case do_delete(inner, rest) {
        Some(#(inner, position)) -> {
          let new = ast.tuple_(list.flatten([pre, [inner], post]))
          Some(#(new, [i, ..position]))
        }
        None -> {
          let elements = list.append(pre, post)
          let position = case list.length(elements) {
            0 -> []
            _ -> [max(0, list.length(pre) - 1)]
          }
          Some(#(ast.tuple_(elements), position))
        }
      }
    }
    e.Record(fields), [i, ..rest] -> {
      let pre = list.take(fields, i)
      let [record, ..post] = list.drop(fields, i)
      case record, rest {
        // delete the whole record even if key selected, use insert for updating
        _, [] | _, [0] -> {
          let fields = list.append(pre, post)
          let position = case list.length(fields) {
            0 -> []
            _ -> [max(0, list.length(pre) - 1)]
          }
          Some(#(e.record(fields), position))
        }
        #(label, inner), [1, ..rest] ->
          case do_delete(inner, rest) {
            Some(#(inner, position)) -> {
              let inner = #(label, inner)
              let new = e.record(list.flatten([pre, [inner], post]))
              let position = [i, 1, ..position]
              Some(#(new, position))
            }
            None -> Some(#(tree, [i]))
          }
      }
    }
    e.Let(pattern, value, then), [0, ..rest] ->
      case delete_pattern(pattern, rest) {
        Some(#(inner, position)) -> {
          let position = [0, ..position]
          let new = ast.let_(inner, value, then)
          Some(#(new, position))
        }
        None -> Some(#(then, []))
      }
    e.Let(pattern, value, then), [1, ..rest] ->
      case do_delete(value, rest) {
        Some(#(inner, position)) -> {
          let position = [1, ..position]
          let new = ast.let_(pattern, inner, then)
          Some(#(new, position))
        }
        None -> Some(#(then, []))
      }
    e.Let(pattern, value, then), [2, ..rest] -> {
      let #(then, position) = case do_delete(then, rest) {
        Some(#(inner, position)) -> #(inner, [2, ..position])
        None -> #(then, position)
      }
      Some(#(ast.let_(pattern, value, then), position))
    }
    e.Function(pattern, body), [0, ..rest] ->
      case delete_pattern(pattern, rest) {
        Some(#(inner, position)) -> {
          let new = ast.function(inner, body)
          Some(#(new, [1, ..position]))
        }
        None -> Some(#(tree, []))
      }
    e.Function(pattern, body), [1, ..rest] ->
      case do_delete(body, rest) {
        Some(#(inner, position)) -> {
          let new = ast.function(pattern, inner)
          Some(#(new, [1, ..position]))
        }
        None -> Some(#(tree, []))
      }
    e.Call(function, with), [0, ..rest] ->
      case do_delete(function, rest) {
        Some(#(inner, position)) -> {
          let new = ast.call(inner, with)
          Some(#(new, [0, ..position]))
        }
        None -> Some(#(tree, []))
      }
    e.Call(function, with), [1, ..rest] ->
      case do_delete(with, rest) {
        Some(#(inner, position)) -> {
          let new = ast.call(function, inner)
          Some(#(new, [1, ..position]))
        }
        None -> Some(#(tree, []))
      }
    e.Case(value, branches), [0, ..rest] ->
      case do_delete(value, rest) {
        Some(#(inner, position)) -> {
          let new = ast.case_(inner, branches)
          Some(#(new, [0, ..position]))
        }
        None -> Some(#(tree, []))
      }
    e.Case(value, branches), [i, ..rest] -> {
      let i = i - 1
      let pre = list.take(branches, i)
      let [branch, ..post] = list.drop(branches, i)
      case branch, rest {
        _, [] | _, [0] -> {
          let branches = list.append(pre, post)
          let position = case list.length(branches) {
            0 -> [0]
            _ -> [max(0, list.length(pre) - 1) + 1]
          }
          Some(#(ast.case_(value, branches), position))
        }
        #(label, pattern, then), [1, ..rest] ->
          case delete_pattern(pattern, rest) {
            Some(#(inner, position)) -> {
              let new = #(label, inner, then)
              let new = ast.case_(value, list.flatten([pre, [new], post]))
              let position = [i + 1, 1, ..position]
              Some(#(new, position))
            }
            None -> Some(#(tree, [i + 1]))
          }
        #(label, pattern, then), [2, ..rest] ->
          case do_delete(then, rest) {
            Some(#(inner, position)) -> {
              let inner = #(label, pattern, inner)
              let new = ast.case_(value, list.flatten([pre, [inner], post]))
              let position = [i + 1, 2, ..position]
              Some(#(new, position))
            }
            None -> Some(#(tree, [i + 1]))
          }
      }
    }
    e.Provider(_, _, _), [_i] -> {
      let new = ast.hole()
      Some(#(new, []))
    }
  }
}

fn delete_pattern(pattern, path) {
  case pattern, path {
    p.Variable(""), [] -> None
    _, [] -> Some(#(p.Variable(""), []))
    p.Tuple(elements), [i] -> {
      let pre = list.take(elements, i)
      let [element, ..post] = list.drop(elements, i)
      case element {
        "" -> {
          let elements = list.append(pre, post)
          let position = case list.length(elements) {
            0 -> []
            _ -> [max(0, list.length(pre) - 1)]
          }
          Some(#(p.Tuple(elements), position))
        }
        _ -> {
          let elements = list.flatten([pre, [""], post])
          Some(#(p.Tuple(elements), [i]))
        }
      }
    }
    p.Record(fields), [i] | p.Record(fields), [i, 0] | p.Record(fields), [i, 1] -> {
      let pre = list.take(fields, i)
      let [_deleted, ..post] = list.drop(fields, i)
      let fields = list.append(pre, post)
      let position = case list.length(fields) {
        0 -> []
        _ -> [max(0, list.length(pre) - 1)]
      }
      Some(#(p.Record(fields), position))
    }
  }
}

fn draft(tree, position) {
  case get_element(tree, position) {
    Expression(#(_, tree)) ->
      case tree {
        e.Binary(content) -> #(None, position, Draft(content))
        _ -> #(None, position, Command)
      }
    Pattern(p.Variable(label), _) -> #(None, position, Draft(label))
    PatternElement(_, label) -> #(None, position, Draft(label))
    RowKey(_, key) -> #(None, position, Draft(key))
    PatternKey(_, key) -> #(None, position, Draft(key))
    PatternFieldBind(_, label) -> #(None, position, Draft(label))
    ProviderConfig(config) -> #(None, position, Draft(config))
    BranchName(name) -> #(None, position, Draft(name))
    _ -> #(None, position, Command)
  }
}

fn variable(tree, position) {
  case get_element(tree, position) {
    // Confusing to replace a whole Let at once.
    Expression(#(_, e.Let(_, _, _))) -> #(None, position, Command)
    Expression(#(metadata, _)) -> {
      let Metadata(scope: scope, ..) = metadata
      let variables = list.map(scope, pair.first)
      let new = Some(replace_expression(tree, position, ast.variable("")))
      #(new, position, Select(variables))
    }
    _ -> #(None, position, Command)
  }
}

fn replace_pattern(tree, position, pattern) {
  let tree = untype(tree)
  // while we don't have arbitrary nesting in patterns don't update replace node, instead
  // manually step up once
  assert Ok(#(let_position, i)) = path.parent(position)
  case get_element(tree, let_position), i {
    Expression(#(_, e.Let(_, value, then))), 0 -> {
      let new = ast.let_(pattern, value, then)
      replace_expression(tree, let_position, new)
    }
    Expression(#(_, e.Function(_, body))), 0 -> {
      let new = ast.function(pattern, body)
      replace_expression(tree, let_position, new)
    }
    Branch(bi), _ -> {
      assert Ok(#(case_position, _)) = path.parent(let_position)
      assert Expression(#(_, e.Case(value, branches))) =
        get_element(tree, case_position)
      let pre = list.take(branches, bi)
      let [branch, ..post] = list.drop(branches, bi)
      let #(label, _, then) = branch
      let branch = #(label, pattern, then)
      let branches = list.flatten([pre, [branch], post])
      let new = ast.case_(value, branches)
      replace_expression(tree, case_position, new)
    }
  }
}

// TODO renaming element TreeNode helps with element in tuple confusion
pub fn get_element(tree: e.Expression(a, b), position) -> Element(a, b) {
  case tree, position {
    _, [] -> Expression(tree)
    #(_, e.Tuple(elements)), [i, ..rest] -> {
      let [child, ..] = list.drop(elements, i)
      get_element(child, rest)
    }
    #(_, e.Record(fields)), [i] -> {
      let [field, ..] = list.drop(fields, i)
      RowField(i, field)
    }
    #(_, e.Record(fields)), [i, 0] -> {
      let [#(key, _), ..] = list.drop(fields, i)
      RowKey(i, key)
    }
    #(_, e.Record(fields)), [i, 1, ..rest] -> {
      let [#(_, child), ..] = list.drop(fields, i)
      get_element(child, rest)
    }
    #(_, e.Tagged(tag, _)), [0] -> Tag(tag)
    #(_, e.Tagged(_, value)), [1, ..rest] -> get_element(value, rest)
    #(_, e.Let(pattern, _, _)), [0, ..rest] -> get_pattern(pattern, rest, tree)
    #(_, e.Let(_, value, _)), [1, ..rest] -> get_element(value, rest)
    #(_, e.Let(_, _, then)), [2, ..rest] -> get_element(then, rest)
    #(_, e.Function(pattern, _)), [0, ..rest] ->
      get_pattern(pattern, rest, tree)
    #(_, e.Function(_, body)), [1, ..rest] -> get_element(body, rest)
    #(_, e.Call(func, _)), [0, ..rest] -> get_element(func, rest)
    #(_, e.Call(_, with)), [1, ..rest] -> get_element(with, rest)
    #(_, e.Case(value, _)), [0, ..rest] -> get_element(value, rest)
    #(_, e.Case(_, branches)), [i, ..rest] ->
      get_branches(branches, i, rest, tree)
    #(_, e.Provider(_, generator, _)), [0] -> ProviderGenerator(generator)
    #(_, e.Provider(config, _, _)), [1] -> ProviderConfig(config)
  }
}

fn get_pattern(pattern, position, parent) {
  case pattern, position {
    pattern, [] -> Pattern(pattern, parent)
    p.Tuple(elements), [i] -> {
      // l.at and this should be an error instead
      let [element, ..] = list.drop(elements, i)
      PatternElement(i, element)
    }
    p.Record(fields), [i] -> {
      // l.at and this should be an error instead
      let [field, ..] = list.drop(fields, i)
      PatternField(i, field)
    }
    p.Record(fields), [i, 0] -> {
      // l.at and this should be an error instead
      let [#(key, _), ..] = list.drop(fields, i)
      PatternKey(i, key)
    }
    p.Record(fields), [i, 1] -> {
      // l.at and this should be an error instead
      let [#(_, bind), ..] = list.drop(fields, i)
      PatternFieldBind(i, bind)
    }
  }
}

fn get_branches(branches, i, rest, parent) {
  let i = i - 1
  let [#(label, pattern, then), ..] = list.drop(branches, i)
  case rest {
    [] -> Branch(i)
    [0] -> BranchName(label)
    // TODO careful with the parent here
    [1, ..rest] -> get_pattern(pattern, rest, parent)
    [2, ..rest] -> get_element(then, rest)
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
      // can't use map at becuase other elements need to be untyped at same time
      // let elements = list.map(elements, untype)
      let pre =
        list.take(elements, index)
        |> list.map(untype)
      let [current, ..post] = list.drop(elements, index)
      let post = list.map(post, untype)
      let updated = map_node(current, rest, mapper)
      let elements = list.flatten([pre, [updated], post])
      ast.tuple_(elements)
    }
    e.Record(fields), [index, 1, ..rest] -> {
      let pre =
        list.take(fields, index)
        |> list.map(untype_field)
      let [#(k, current), ..post] = list.drop(fields, index)
      let post = list.map(post, untype_field)
      let updated = map_node(current, rest, mapper)
      let fields = list.flatten([pre, [#(k, updated)], post])
      e.record(fields)
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
    e.Case(value, branches), [path_index, 2, ..rest] -> {
      let branches =
        list.index_map(
          branches,
          fn(branch_index, branch) {
            let #(label, pattern, then) = branch
            let then = case branch_index + 1 == path_index {
              True -> map_node(then, rest, mapper)
              False -> untype(then)
            }
            #(label, pattern, then)
          },
        )
      ast.case_(untype(value), branches)
    }
  }
}
