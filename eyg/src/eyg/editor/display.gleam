import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import eyg/ast/path
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer.{Metadata}

pub fn is_multiexpression(expression) {
  case expression {
    #(_, e.Let(_, _, _)) -> True
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
  Display(position: List(Int), selection: Selection, errored: Bool)
}

pub fn marker(display) {
  let Display(position: position, ..) = display
  position_to_marker(position)
}

pub fn position_to_marker(position) {
  let position =
    position
    |> list.map(int.to_string)
    |> list.intersperse(",")
  string.join(["p:", ..position])
}

pub fn is_target(display) {
  let Display(selection: selection, ..) = display
  case selection {
    Above([]) -> True
    _ -> False
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
pub fn show_value(metadata) {
  let Display(selection: selection, ..) = metadata
  case selection {
    Above([]) -> False
    Above([0, .._]) | Above([1, .._]) -> True
    _ -> False
  }
  // io.debug(metadata)
}

// if not selected print value minimal
// if taget print value minimal, this is where peek in is valuable
// if target in pattern or value print full
// down from pattern should move into let, if block
// it's a nice idea to put value in expression and pattern. but there is no analog to discard.
// unless we treat it as empty string variable.
pub fn display(tree, position, selection, editor) {
  let #(Metadata(type_: type_, ..), expression) = tree
  let errored = case type_ {
    Ok(_) -> False
    Error(_) -> True
  }
  let metadata = Display(position, selection, errored)
  case expression {
    e.Binary(content) -> #(metadata, e.Binary(content))
    e.Integer(content) -> #(metadata, e.Integer(content))
    e.Tuple(elements) -> {
      let display_element = fn(index, element) {
        let position = path.append(position, index)
        let selection = child_selection(selection, index)
        display(element, position, selection, editor)
      }
      let elements = list.index_map(elements, display_element)
      #(metadata, e.Tuple(elements))
    }
    e.Row(fields) -> {
      let display_field = fn(index, field) {
        let #(label, value) = field
        let position = list.append(position, [index, 1])
        let selection = child_selection(child_selection(selection, index), 1)
        #(label, display(value, position, selection, editor))
      }
      let fields = list.index_map(fields, display_field)
      #(metadata, e.Row(fields))
    }
    e.Variable(label) -> #(metadata, e.Variable(label))
    e.Let(pattern, value, then) -> {
      let value =
        display(
          value,
          path.append(position, 1),
          child_selection(selection, 1),
          editor,
        )
      let then =
        display(
          then,
          path.append(position, 2),
          child_selection(selection, 2),
          editor,
        )
      #(metadata, e.Let(pattern, value, then))
    }
    e.Function(from, to) -> {
      let to =
        display(
          to,
          path.append(position, 1),
          child_selection(selection, 1),
          editor,
        )
      #(metadata, e.Function(from, to))
    }
    e.Call(function, with) -> {
      let function =
        display(
          function,
          path.append(position, 0),
          child_selection(selection, 0),
          editor,
        )
      let with =
        display(
          with,
          path.append(position, 1),
          child_selection(selection, 1),
          editor,
        )
      #(metadata, e.Call(function, with))
    }
    e.Provider(config, generator) -> #(metadata, e.Provider(config, generator))
  }
}

// properrty display -> untype should be equal
// property type -> untype should be equal
pub type Pattern {
  Discard
}

pub fn display_pattern(metadata, pattern) {
  let Display(position: position, selection: selection, ..) = metadata
  //   ast&path.child
  //   is always 0 but that's a coincidence of fn and let
  let position = path.append(position, 0)
  let selection = child_selection(selection, 0)
  let display = Display(position, selection, False)
}

// display_elements takes care of _ in label too
pub fn display_pattern_elements(display, elements) {
  let Display(position: position, selection: selection, ..) = display
  list.index_map(
    elements,
    fn(i, e) {
      let position = path.append(position, i)
      let selection = child_selection(selection, i)
      let value = case e {
        Some(label) -> label
        None -> "_"
      }
      #(Display(position, selection, False), value)
    },
  )
}

pub fn display_pattern_fields(display, fields) {
  let Display(position: position, selection: selection, ..) = display
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
        Display(position, selection, False),
        Display(label_position, label_selection, False),
        label,
        Display(value_position, value_selection, False),
        bind,
      )
    },
  )
}

pub fn display_expression_fields(display, fields) {
  let Display(position: position, selection: selection, ..) = display
  list.index_map(
    fields,
    fn(i, f) {
      let position = path.append(position, i)
      let selection = child_selection(selection, i)
      let label_position = path.append(position, 0)
      let label_selection = child_selection(selection, 0)
      let #(label, value) = f
      #(
        Display(position, selection, False),
        Display(label_position, label_selection, False),
        label,
        value,
      )
    },
  )
}

pub fn display_unit_variant(display) {
  let Display(position: position, selection: selection, ..) = display
  let position = path.append(position, 0)
  let selection = child_selection(selection, 0)
  let display = Display(position, selection, False)
}
