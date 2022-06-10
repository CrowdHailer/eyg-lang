import gleam/dynamic.{Dynamic}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import eyg/ast/path
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/editor/editor
import eyg/typer.{Metadata}
import eyg/typer/monotype as t
import eyg/editor/type_info
import eyg/analysis

pub fn is_multiexpression(expression) {
  case expression {
    #(_, e.Let(_, _, _)) -> True
    _ -> False
  }
}

pub fn is_unit(expression) {
  case expression {
    #(_, e.Tuple([])) -> True
    _ -> False
  }
}

pub type Selection {
  // Note Target status is Above with empty list
  Above(rest: List(Int))
  Within
  Neither
}

pub type Display {
  //   make this marker String path if we put metadata in patterns
  Display(
    position: List(Int),
    selection: Selection,
    type_: String,
    errored: Bool,
    expanded: Bool,
  )
}

pub fn marker(display) {
  let Display(position: position, ..) = display
  position_to_marker(position)
}

pub fn collapse_marker(display) {
  let Display(position: position, ..) = display
  let position = path.append(position, 1)
  position_to_marker(position)
}

pub fn position_to_marker(position) {
  let position =
    position
    |> list.map(int.to_string)
    |> list.intersperse(",")
  string.concat(["p:", ..position])
}

pub fn is_target(display) {
  let Display(selection: selection, ..) = display
  case selection {
    Above([]) -> True
    _ -> False
  }
}

// returns bool if error
pub fn target_type(editor) {
  let editor.Editor(cache: cache, selection: selection, ..) = editor
  case selection {
    Some(path) ->
      case editor.get_element(cache.typed, path) {
        editor.Expression(#(_, e.Let(_, value, _))) ->
          expression_type(value, cache.typer, editor.harness.native_to_string)
        editor.Expression(expression) ->
          expression_type(
            expression,
            cache.typer,
            editor.harness.native_to_string,
          )
        _ -> #(False, "")
      }
    None -> #(False, "")
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
      |> analysis.shrink
      |> type_info.to_string(native_to_string),
    )
    Error(reason) -> #(
      True,
      type_info.reason_to_string(reason, native_to_string),
    )
  }
}

fn child_selection(selection, child) {
  case selection {
    Above([x, ..rest]) if x == child -> Above(rest)
    Above([]) -> Within
    Above(_) -> Neither
    Within -> Within
    Neither -> Neither
  }
}

// within is not true for let and 2
pub fn show_let_value(metadata) {
  let Display(selection: selection, ..) = metadata
  case selection {
    Above([]) -> False
    Above([0, ..]) | Above([1, ..]) -> True
    _ -> False
  }
}

pub fn show_expression(metadata) {
  let Display(selection: selection, ..) = metadata
  case selection {
    Above([]) -> False
    Above(_) -> True
    _ -> False
  }
}

pub fn display(editor) {
  let editor.Editor(source: source, selection: selection, ..) = editor
  let selection = case selection {
    Some(path) -> Above(path)
    None -> Neither
  }
  do_display(editor.cache.typed, path.root(), selection, editor)
}

// if not selected print value minimal
// if taget print value minimal, this is where peek in is valuable
// if target in pattern or value print full
// down from pattern should move into let, if block
// it's a nice idea to put value in expression and pattern. but there is no analog to discard.
// unless we treat it as empty string variable.
pub fn do_display(tree, position, selection, editor) {
  let #(Metadata(type_: type_, ..), expression) = tree
  let editor.Editor(expanded: expanded, ..) = editor
  let typer: typer.Typer(_) = editor.cache.typer
  let #(errored, type_) = case type_ {
    Ok(type_) -> #(
      False,
      type_info.to_string(
        t.resolve(type_, typer.substitutions),
        editor.harness.native_to_string,
      ),
    )
    Error(_) -> #(True, "")
  }
  let metadata = Display(position, selection, type_, errored, expanded)
  case expression {
    e.Binary(content) -> #(metadata, e.Binary(content))
    e.Tuple(elements) -> {
      let display_element = fn(index, element) {
        let position = path.append(position, index)
        let selection = child_selection(selection, index)
        do_display(element, position, selection, editor)
      }
      let elements = list.index_map(elements, display_element)
      #(metadata, e.Tuple(elements))
    }
    e.Record(fields) -> {
      let display_field = fn(index, field) {
        let #(label, value) = field
        let position = list.append(position, [index, 1])
        let selection = child_selection(child_selection(selection, index), 1)
        #(label, do_display(value, position, selection, editor))
      }
      let fields = list.index_map(fields, display_field)
      #(metadata, e.Record(fields))
    }
    e.Access(value, label) -> #(
      metadata,
      e.Access(
        do_display(
          value,
          path.append(position, 0),
          child_selection(selection, 0),
          editor,
        ),
        label,
      ),
    )
    e.Tagged(tag, value) -> #(
      metadata,
      e.Tagged(
        tag,
        do_display(
          value,
          path.append(position, 1),
          child_selection(selection, 1),
          editor,
        ),
      ),
    )
    e.Variable(label) -> #(metadata, e.Variable(label))
    e.Let(pattern, value, then) -> {
      let value =
        do_display(
          value,
          path.append(position, 1),
          child_selection(selection, 1),
          editor,
        )
      let then =
        do_display(
          then,
          path.append(position, 2),
          child_selection(selection, 2),
          editor,
        )
      #(metadata, e.Let(pattern, value, then))
    }
    e.Function(from, to) -> {
      let to =
        do_display(
          to,
          path.append(position, 1),
          child_selection(selection, 1),
          editor,
        )
      #(metadata, e.Function(from, to))
    }
    e.Call(function, with) -> {
      let function =
        do_display(
          function,
          path.append(position, 0),
          child_selection(selection, 0),
          editor,
        )
      let with =
        do_display(
          with,
          path.append(position, 1),
          child_selection(selection, 1),
          editor,
        )
      #(metadata, e.Call(function, with))
    }
    e.Case(value, branches) -> {
      let value =
        do_display(
          value,
          path.append(position, 0),
          child_selection(selection, 0),
          editor,
        )
      let branches =
        list.index_map(
          branches,
          fn(index, branch) {
            let index = index + 1
            let #(name, pattern, then) = branch
            let position = list.append(position, [index, 2])
            let selection =
              child_selection(child_selection(selection, index), 2)
            #(name, pattern, do_display(then, position, selection, editor))
          },
        )
      #(metadata, e.Case(value, branches))
    }
    e.Hole -> #(metadata, e.Hole)
    e.Provider(config, generator, generated) ->
      // coerce back and forth because the expression does not represent the recursion we need.
      // There are cases when nothing is shown here
      // TODO better typing of provider with stuff
      case dynamic.from(generated) == dynamic.from(Nil) {
        True -> #(metadata, e.Provider(config, generator, generated))
        False -> {
          let generated: e.Expression(
            Metadata(n),
            e.Expression(Metadata(n), Dynamic),
          ) = unsafe_coerce(generated)
          let generated =
            do_display(
              generated,
              path.append(position, 1),
              child_selection(selection, 1),
              editor,
            )
          #(metadata, e.Provider(config, generator, unsafe_coerce(generated)))
        }
      }
  }
}

pub external fn unsafe_coerce(a) -> b =
  "../../eyg_utils.js" "identity"

// Don't use pattern as separate pattern element functions are used to render further into tree
pub fn display_pattern(metadata, _pattern) {
  let Display(position: position, selection: selection, expanded: expanded, ..) =
    metadata
  //   ast&path.child
  //   is always 0 but that's a coincidence of fn and let
  let position = path.append(position, 0)
  let selection = child_selection(selection, 0)
  Display(position, selection, "", False, expanded)
}

// display_elements takes care of _ in label too
pub fn display_pattern_elements(display, elements) {
  let Display(position: position, selection: selection, expanded: expanded, ..) =
    display
  list.index_map(
    elements,
    fn(i, bind) {
      let position = path.append(position, i)
      let selection = child_selection(selection, i)
      // Not the best solution. printing an underscore is just done for view and probably belongs in CSS
      let value = case bind {
        "" -> "_"
        label -> label
      }
      #(Display(position, selection, "", False, expanded), value)
    },
  )
}

pub fn display_pattern_fields(display, fields) {
  let Display(position: position, selection: selection, expanded: expanded, ..) =
    display
  list.index_map(
    fields,
    fn(i, f) {
      let position = path.append(position, i)
      let selection = child_selection(selection, i)
      let label_position = path.append(position, 0)
      let label_selection = child_selection(selection, 0)
      let value_position = path.append(position, 1)
      let value_selection = child_selection(selection, 1)
      let #(label, bind) = f
      #(
        Display(position, selection, "", False, expanded),
        Display(label_position, label_selection, "", False, expanded),
        label,
        Display(value_position, value_selection, "", False, expanded),
        bind,
      )
    },
  )
}

pub fn display_expression_fields(display, fields) {
  let Display(position: position, selection: selection, expanded: expanded, ..) =
    display
  list.index_map(
    fields,
    fn(i, f) {
      let position = path.append(position, i)
      let selection = child_selection(selection, i)
      let label_position = path.append(position, 0)
      let label_selection = child_selection(selection, 0)
      let #(label, value) = f
      #(
        Display(position, selection, "", False, expanded),
        Display(label_position, label_selection, "", False, expanded),
        label,
        value,
      )
    },
  )
}

pub fn display_access_key(display) {
  let Display(position: position, selection: selection, expanded: expanded, ..) =
    display
  let position = path.append(position, 1)
  let selection = child_selection(selection, 1)
  Display(position, selection, "", False, expanded)
}

pub fn display_tag(display) {
  let Display(position: position, selection: selection, expanded: expanded, ..) =
    display
  let position = path.append(position, 0)
  let selection = child_selection(selection, 0)
  Display(position, selection, "", False, expanded)
}

pub fn for_provider_config(display) {
  let Display(position: position, selection: selection, expanded: expanded, ..) =
    display
  let position = path.append(position, 1)
  let selection = child_selection(selection, 1)
  Display(position, selection, "", False, expanded)
}

pub fn for_provider_generator(generator, display) {
  let Display(position: position, selection: selection, expanded: expanded, ..) =
    display
  let position = path.append(position, 0)
  let selection = child_selection(selection, 0)
  let display = Display(position, selection, "", False, expanded)
  #(e.generator_to_string(generator), display)
}

pub fn for_branches(branches, display) {
  list.index_map(
    branches,
    fn(index, branch) { display_branch(index, branch, display) },
  )
}

fn display_branch(index, branch, match_meta) {
  let Display(position: position, selection: selection, expanded: expanded, ..) =
    match_meta
  let #(name, pattern, then) = branch
  let branch_position = path.append(position, index + 1)
  let branch_selection = child_selection(selection, index + 1)
  let branch_display =
    Display(branch_position, branch_selection, "", False, expanded)

  let label_position = path.append(branch_position, 0)
  let label_selection = child_selection(branch_selection, 0)
  let label_display =
    Display(label_position, label_selection, "", False, expanded)

  let pattern_position = path.append(branch_position, 1)
  let pattern_selection = child_selection(branch_selection, 1)
  let pattern_display =
    Display(pattern_position, pattern_selection, "", False, expanded)

  #(branch_display, label_display, name, pattern_display, pattern, then)
}
