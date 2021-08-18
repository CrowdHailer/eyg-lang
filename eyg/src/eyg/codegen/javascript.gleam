import gleam/io
import gleam/int
import gleam/list
import gleam/string
import eyg/ast.{Binary, Call, Function, Let, Name, Row, Tuple, Variable}
import eyg/ast/pattern
import eyg/codegen/utilities.{
  indent, join, squash, wrap_lines, wrap_single_or_multiline,
}

pub fn maybe_wrap_expression(expression, state) {
  case expression {
    Let(_, _, _) | Name(_, _) -> {
      let rendered = render(expression, in_tail(True, state))
      ["(() => {"]
      |> list.append(indent(rendered))
      |> list.append(["})()"])
    }
    _ -> render(expression, in_tail(False, state))
  }
}

fn wrap_return(lines, state) {
  let #(in_tail, _) = state

  case in_tail {
    True -> wrap_lines("return ", lines, ";")
    False -> lines
  }
}

pub fn in_tail(in_tail, state) {
  let #(_, scope) = state
  #(in_tail, scope)
}

fn with_assignment(label, state) {
  let #(in_tail, scope) = state
  let scope = [label, ..scope]
  #(in_tail, scope)
}

fn count_label(state, label) {
  let #(_, scope) = state

  list.fold(
    scope,
    0,
    fn(l, count) {
      case l == label {
        True -> count + 1
        False -> count
      }
    },
  )
}

fn render_label(label, state) {
  case label {
    "self" -> "self"
    label ->
      case count_label(state, label) {
        // if not previously rendered must be an external thing
        0 -> label
        count -> join([label, "$", int.to_string(count)])
      }
  }
}

pub fn render(tree, state) {
  case tree {
    // TODO escape
    Binary(content) -> wrap_return([join(["\"", content, "\""])], state)
    Tuple(elements) ->
      list.map(elements, maybe_wrap_expression(_, state))
      |> wrap_single_or_multiline(",", "[", "]")
      |> wrap_return(state)
    Row(fields) ->
      list.map(
        fields,
        fn(field) {
          let #(name, value) = field
          wrap_lines(
            string.concat(name, ": "),
            maybe_wrap_expression(value, state),
            "",
          )
        },
      )
      |> wrap_single_or_multiline(",", "{", "}")
      |> wrap_return(state)
    Let(pattern, value, then) -> {
      let value = maybe_wrap_expression(value, state)
      let #(assignment, state) = case pattern {
        pattern.Variable(label) -> {
          let state = with_assignment(label, state)
          let assignment = join(["let ", render_label(label, state), " = "])
          #(wrap_lines(assignment, value, ";"), state)
        }
        pattern.Tuple(elements) -> {
          let #(elements, state) =
            list.map_state(
              elements,
              state,
              fn(label, state) {
                let state = with_assignment(label, state)
                #(render_label(label, state), state)
              },
            )
          let destructure =
            elements
            |> list.intersperse(", ")
            // wrap_lines not a good name here
            |> wrap_lines("[", _, "]")
            |> join()
          let assignment = join(["let ", destructure, " = "])
          #(wrap_lines(assignment, value, ";"), state)
        }
      }
      list.append(assignment, render(then, state))
    }
    Variable(label) -> wrap_return([render_label(label, state)], state)
    Call(function, with) -> {
      assert Tuple(with) = with
      let function = render(function, in_tail(False, state))
      let with = list.map(with, maybe_wrap_expression(_, state))
      let args_string = wrap_single_or_multiline(with, ",", "(", ")")
      squash(function, args_string)
      |> wrap_return(state)
    }
    _ -> {
      io.debug(tree)
      todo("render this node")
    }
  }
}
