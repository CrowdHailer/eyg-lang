import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer
import eyg/typer/monotype as t
import eyg/codegen/utilities.{
  indent, squash, wrap_lines, wrap_single_or_multiline,
}

pub type Generator {

  // self is the name being given in a let clause
  Generator(
    in_tail: Bool,
    scope: List(String),
    typer: typer.Typer,
    self: Option(String),
  )
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
  let Generator(in_tail: in_tail, ..) = state

  case in_tail {
    True -> wrap_lines("return ", lines, ";")
    False -> lines
  }
}

pub fn in_tail(in_tail, state) {
  Generator(..state, in_tail: in_tail)
}

fn with_assignment(label, state) {
  let Generator(scope: scope, ..) = state
  let scope = [label, ..scope]
  Generator(..state, scope: scope)
}

fn count_label(state, label) {
  let Generator(scope: scope, ..) = state

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
    label ->
      case count_label(state, label) {
        // if not previously rendered must be an external thing
        0 -> label
        count -> string.join([label, "$", int.to_string(count)])
      }
  }
}

fn render_function_name(state) {
  let Generator(self: self, scope: scope, ..) = state
  case self {
    Some(label) -> {
      let count = count_label(state, label) + 1
      string.join([label, "$", int.to_string(count)])
    }
    None -> ""
  }
}

pub fn render_to_string(expression, typer) {
  render(expression, Generator(False, [], typer, None))
  |> list.intersperse("\n")
  |> string.join()
}

pub fn render_in_function(expression, typer) {
  render(expression, Generator(True, [], typer, None))
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
  let #(context, tree) = tree
  case tree {
    // TODO escape
    e.Binary(content) ->
      wrap_return([string.join(["\"", content, "\""])], state)
    e.Tuple(elements) -> {
      let state = Generator(..state, self: None)
      list.map(elements, maybe_wrap_expression(_, state))
      |> wrap_single_or_multiline(",", "[", "]")
      |> wrap_return(state)
    }
    e.Row(fields) -> {
      let state = Generator(..state, self: None)
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
    }
    e.Let(pattern, value, then) -> {
      let state = Generator(..state, self: None)
      let value_state = case pattern {
        p.Variable(label) ->
          // can't use with assignment here. It messes up rendering let a = a
          Generator(..state, self: Some(label))
        // |> with_assignment(label)
        _ -> state
      }
      // value needs to be rendered first to use the correct count for the variable numbers
      let value = maybe_wrap_expression(value, value_state)
      // self is only present in value
      let #(bind, state) = render_pattern(pattern, state)
      let assignment = string.join(["let ", bind, " = "])
      list.append(wrap_lines(assignment, value, ";"), render(then, state))
    }
    e.Variable(label) ->
      wrap_return([render_label(label, Generator(..state, self: None))], state)
    e.Function(pattern, body) -> {
      let #(bind, state) = render_pattern(pattern, state)
      let name = render_function_name(state)
      let start = string.join(["(function ", name, "(", bind, ") {"])
      // if function given a self name it is available in the body
      let state = case state.self {
        None -> state
        Some(label) -> with_assignment(label, Generator(..state, self: None))
      }
      case render(body, in_tail(True, state)) {
        [single] -> [string.join([start, " ", single, " })"])]
        lines ->
          [start, ..indent(lines)]
          |> list.append(["})"])
      }
      |> wrap_return(state)
    }
    e.Call(function, with) -> {
      let state = Generator(..state, self: None)
      let function = render(function, in_tail(False, state))
      let with = wrap_lines("(", maybe_wrap_expression(with, state), ")")
      squash(function, with)
      |> wrap_return(state)
    }
    e.Provider("", e.Hole) -> ["(() => {throw 'Reached todo in the code'})()"]
    e.Provider(config, e.Loader) -> {
      let typer.Metadata(type_: Ok(expected), ..) = context
      let Generator(typer: typer, ..) = state
      let typer.Typer(substitutions: substitutions, ..) = typer
      let loader = t.resolve(expected, substitutions)
      case loader {
        t.Function(_from, result) ->
          case result {
            t.Function(t.Tuple([t.Function(usable, _), t.Function(_, _)]), out) -> {
              io.debug(usable)
              [
                "((ast) => {",
                string.join([
                  "  return window.compile(",
                  t.literal(usable),
                  ", ast)",
                ]),
                "})",
              ]
            }
            _ -> [
              "(() => {throw 'Failed to build provider for ",
              t.to_string(loader),
              "'})()",
            ]
          }
      }
    }
    e.Provider(config, generator) -> {
      let typer.Metadata(type_: Ok(expected), ..) = context
      let Generator(typer: typer, ..) = state
      let typer.Typer(substitutions: substitutions, ..) = typer
      let expected = t.resolve(expected, substitutions)
      let tree = e.generate(generator, config, expected)
      let #(typed, typer) =
        typer.infer(tree, expected, #(typer, typer.root_scope([])))
      let state = Generator(..state, typer: typer)
      io.debug(list.length(typer.inconsistencies))
      render(typed, state)
    }
  }
}
