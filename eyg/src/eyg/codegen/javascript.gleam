import gleam/dynamic.{Dynamic}
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

pub type Generator(n) {

  // self is the name being given in a let clause
  Generator(
    in_tail: Bool,
    scope: List(String),
    typer: typer.Typer(n),
    self: Option(String),
    // Scope and self can me moved out into the metadata
    native_to_string: fn(n) -> String,
  )
}

external fn do_eval(String) -> Dynamic =
  "../../harness.js" "run"

pub fn eval(tree, typer, native_to_string) {
  let code = render_in_function(tree, typer, native_to_string)
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
  let Generator(self: self, ..) = state
  case self {
    Some(label) -> {
      let count = count_label(state, label) + 1
      string.join([label, "$", int.to_string(count)])
    }
    None -> ""
  }
}

pub fn render_to_string(expression, typer, native_to_string) {
  render(expression, Generator(False, [], typer, None, native_to_string))
  |> list.intersperse("\n")
  |> string.join()
}

pub fn render_in_function(expression, typer, native_to_string) {
  render(expression, Generator(True, [], typer, None, native_to_string))
  |> list.intersperse("\n")
  |> string.join()
}

fn render_pattern(pattern, state) {
  case pattern {
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
            let state = with_assignment(label, state)
            #(render_label(label, state), state)
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

// https://www.w3schools.com/js/js_strings.asp
// quotes and backslash. Note there is also typewriter charachters I have not tackled here.
fn escape_string(raw) {
  raw
  // Need to replace user slashes first so that slashed from later escape sequences are kept
  |> string.replace("\\", "\\\\")
  |> string.replace("'", "\\'")
  |> string.replace("\"", "\\\"")
}

pub fn render(
  tree: e.Expression(
    typer.Metadata(n),
    e.Expression(typer.Metadata(n), Dynamic),
  ),
  state,
) {
  let #(context, tree) = tree
  case tree {
    e.Binary(content) ->
      wrap_return([string.join(["\"", escape_string(content), "\""])], state)
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
    e.Case(value, branches) -> {
      let value = render(value, in_tail(False, state))
      let branches =
        list.map(
          branches,
          fn(branch) {
            let #(label, pattern, then) = branch
            let #(bind, state) = render_pattern(pattern, state)
            let start = string.join([label, ": (", bind, ") => {"])
            case render(then, in_tail(True, state)) {
              [single] -> [string.join([start, " ", single, " },"])]
              lines ->
                [start, ..indent(lines)]
                |> list.append(["},"])
            }
          },
        )
        // |> wrap_return(state
        // |> wrap_single_or_multiline("(((((", ",", "####")
        |> list.flatten()
        |> indent()
      // value might be multiline
      // let x = wrap_single_or_multiline(branches, "(((((", ",", "####")
      list.append(squash(value, ["({"]), list.append(branches, ["})"]))
      |> wrap_return(state)
    }

    // |> wrap_return(state)
    e.Provider("", e.Hole, _) -> [
      "(() => {throw 'Reached todo in the code'})()",
    ]
    e.Provider(_config, e.Loader, _) -> {
      let typer.Metadata(type_: Ok(expected), ..) = context
      let Generator(typer: typer, ..) = state
      let typer.Typer(substitutions: substitutions, ..) = typer
      let loader = t.resolve(expected, substitutions)
      case loader {
        t.Function(_from, result) ->
          case result {
            t.Function(t.Tuple([t.Function(usable, _), t.Function(_, _)]), _out) -> [
              "((ast) => {",
              string.join([
                // compile not implemented should probably be env/platform/browser
                "  return window.compile(",
                t.literal(usable),
                ", ast)",
              ]),
              "})",
            ]
            _ -> [
              "(() => {throw 'Failed to build provider for ",
              t.to_string(loader, state.native_to_string),
              "'})()",
            ]
          }
      }
    }
    // This type is recursive starts with generated ends up with nil, in the nil case We should never have a provider?
    e.Provider(_, _, generated) -> render(unsafe_coerce(generated), state)
  }
}

pub external fn unsafe_coerce(a) -> b =
  "../../eyg_utils.js" "identity"
