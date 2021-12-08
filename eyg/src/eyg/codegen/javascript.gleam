import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype
import eyg/typer/polytype.{State}
import eyg/typer
import eyg/codegen/utilities.{
  indent, squash, wrap_lines, wrap_single_or_multiline,
}

// TODO move to dynamic type
external fn do_eval(String) -> anything =
  "../../harness.js" "run"

pub fn eval(tree, typer) {
  let code = render_in_function(tree, typer)
  string.join(["(function(equal){\n", code, "})(equal)"])
  |> do_eval
}

pub fn maybe_wrap_expression(expression, state) {
  case expression {
    #(_, e.Let(_, _, _)) -> {
      let rendered = render(expression, in_tail(True, state))
      ["(() => {"]
      |> list.append(indent(rendered))
      |> list.append(["})()"])
    }
    _ -> render(expression, in_tail(False, state))
  }
}

fn wrap_return(lines, state) {
  let #(in_tail, _, _) = state

  case in_tail {
    True -> wrap_lines("return ", lines, ";")
    False -> lines
  }
}

pub fn in_tail(in_tail, state) {
  let #(_, scope, typer) = state
  #(in_tail, scope, typer)
}

fn with_assignment(label, state) {
  let #(in_tail, scope, typer) = state
  let scope = [label, ..scope]
  #(in_tail, scope, typer)
}

fn count_label(state, label) {
  let #(_, scope, _) = state

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
        count -> string.join([label, "$", int.to_string(count)])
      }
  }
}

pub fn render_to_string(expression, typer) {
  render(expression, #(False, [], typer))
  |> list.intersperse("\n")
  |> string.join()
}

pub fn render_in_function(expression, typer) {
  render(expression, #(True, [], typer))
  |> list.intersperse("\n")
  |> string.join()
}

fn render_pattern(pattern, state) {
  case pattern {
    p.Discard -> #("_", state)
    p.Variable(label) -> {
      let state = with_assignment(label, state)
      let bind = render_label(label, state)
      #(bind, state)
    }
    p.Tuple(elements) -> {
      let #(elements, state) =
        list.map_state(
          elements,
          state,
          fn(label, state) {
            let label2 = case label {
              Some(l) -> l
              None -> "_"
            }
            let state = with_assignment(label2, state)
            #(render_label(label2, state), state)
          },
        )
      let bind =
        elements
        |> list.intersperse(", ")
        // wrap_lines not a good name here
        |> wrap_lines("[", _, "]")
        |> string.join()
      #(bind, state)
    }
    p.Row(fields) -> {
      let #(fields, state) =
        list.map_state(
          fields,
          state,
          fn(field, state) {
            let #(row_name, label) = field
            let state = with_assignment(label, state)
            let field =
              string.join([row_name, ": ", render_label(label, state)])
            #(field, state)
          },
        )
      let bind =
        fields
        |> list.intersperse(", ")
        // wrap_lines not a good name here
        |> wrap_lines("{", _, "}")
        |> string.join()
      #(bind, state)
    }
  }
}

pub fn render(tree, state) {
  let hole_func = ast.generate_hole

  let #(context, tree) = tree
  case tree {
    // TODO escape
    e.Binary(content) ->
      wrap_return([string.join(["\"", content, "\""])], state)
    e.Tuple(elements) ->
      list.map(elements, maybe_wrap_expression(_, state))
      |> wrap_single_or_multiline(",", "[", "]")
      |> wrap_return(state)
    e.Row(fields) ->
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
    e.Let(pattern, value, then) -> {
      // value needs to be rendered first to use the correct count for the variable numbers
      let value = maybe_wrap_expression(value, state)
      let #(bind, state) = render_pattern(pattern, state)
      let assignment = string.join(["let ", bind, " = "])
      list.append(wrap_lines(assignment, value, ";"), render(then, state))
    }
    e.Variable(label) -> wrap_return([render_label(label, state)], state)
    e.Function(pattern, body) -> {
      let #(bind, state) = render_pattern(pattern, state)
      let start = string.join(["(function self(", bind, ") {"])
      case render(body, in_tail(True, state)) {
        [single] -> [string.join([start, " ", single, " })"])]
        lines ->
          [start, ..indent(lines)]
          |> list.append(["})"])
      }
      |> wrap_return(state)
    }
    e.Call(function, with) -> {
      let function = render(function, in_tail(False, state))
      let with = wrap_lines("(", maybe_wrap_expression(with, state), ")")
      squash(function, with)
      |> wrap_return(state)
    }
    e.Provider("", g) if g == hole_func -> [
      "(() => {throw 'Reached todo in the code'})()",
    ]
    x -> {
      io.debug(x)
      todo("handle this case")
    }
  }
}
