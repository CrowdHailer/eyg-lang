import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import misc
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
  // TODO move scope to have numbers in the typer
  // TODO move native out as never render native type
  Generator(
    in_tail: Bool,
    scope: List(String),
    typer: typer.Typer(n),
    self: Option(String),
  )
}

// Scope and self can me moved out into the metadata
external fn do_eval(String) -> Dynamic =
  "../../harness.js" "run"

pub fn eval(tree, typer) {
  let code = render_in_function(tree, typer)
  string.concat(["(function(equal){\n", code, "})(equal)"])
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
    fn(count, l) {
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
        count -> string.concat([label, "$", int.to_string(count)])
      }
  }
}

fn render_function_name(state) {
  let Generator(self: self, ..) = state
  case self {
    Some(label) -> {
      let count = count_label(state, label) + 1
      string.concat([label, "$", int.to_string(count)])
    }
    None -> ""
  }
}

pub fn render_to_string(expression, typer) {
  render(expression, Generator(False, [], typer, None))
  |> list.intersperse("\n")
  |> string.concat()
}

pub fn render_in_function(expression, typer) {
  render(expression, Generator(True, [], typer, None))
  |> list.intersperse("\n")
  |> string.concat()
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
        misc.map_state(
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
        |> string.concat()
      #(bind, state)
    }
    p.Record(fields) -> {
      let #(fields, state) =
        misc.map_state(
          fields,
          state,
          fn(field, state) {
            let #(field_name, binding) = field
            let state = with_assignment(binding, state)
            let field =
              string.concat([field_name, ": ", render_label(binding, state)])
            #(field, state)
          },
        )
      let bind =
        fields
        |> list.intersperse(", ")
        // wrap_lines not a good name here
        |> wrap_lines("{", _, "}")
        |> string.concat()
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
      wrap_return([string.concat(["\"", escape_string(content), "\""])], state)
    e.Tuple(elements) -> {
      let state = Generator(..state, self: None)
      list.map(elements, maybe_wrap_expression(_, state))
      |> wrap_single_or_multiline(",", "[", "]")
      |> wrap_return(state)
    }
    e.Record(fields) -> {
      let state = Generator(..state, self: None)
      list.map(
        fields,
        fn(field) {
          let #(name, value) = field
          wrap_lines(
            string.concat([name, ": "]),
            maybe_wrap_expression(value, state),
            "",
          )
        },
      )
      |> wrap_single_or_multiline(",", "{", "}")
      |> wrap_return(state)
    }
    // TODO escape tag
    e.Tagged(tag, value) -> {
      let state = Generator(..state, self: None)
      let start = string.concat(["{", tag, ":"])
      case maybe_wrap_expression(value, state) {
        [single] -> [string.concat([start, " ", single, "}"])]
        lines ->
          [start, ..indent(lines)]
          |> list.append(["}"])
      }
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
      let assignment = string.concat(["let ", bind, " = "])
      list.append(wrap_lines(assignment, value, ";"), render(then, state))
    }
    e.Variable(label) ->
      wrap_return([render_label(label, Generator(..state, self: None))], state)
    e.Function(pattern, body) -> {
      let #(bind, state) = render_pattern(pattern, state)
      let name = render_function_name(state)
      let start = string.concat(["(function ", name, "(", bind, ") {"])
      // if function given a self name it is available in the body
      let state = case state.self {
        None -> state
        Some(label) -> with_assignment(label, Generator(..state, self: None))
      }
      case render(body, in_tail(True, state)) {
        [single] -> [string.concat([start, " ", single, " })"])]
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
      let branches =
        list.flat_map(
          branches,
          fn(branch) {
            let #(label, pattern, then) = branch
            let #(bind, state) = render_pattern(pattern, state)
            let assignment = string.concat(["let ", bind, " = $.", label, ";"])
            let clause =
              indent([assignment, ..render(then, in_tail(True, state))])
            let match =
              string.concat(["else if (Object.hasOwn($, \"", label, "\")) {"])
            list.append([match, ..clause], ["}"])
          },
        )
      let branches =
        ["if (false) {}", ..branches]
        |> indent()
      let pre = "(function ($){"
      let function = list.append([pre, ..branches], ["})"])
      let with = wrap_lines("(", maybe_wrap_expression(value, state), ")")
      squash(function, with)
      |> wrap_return(state)
    }

    // |> wrap_return(state)
    e.Hole -> ["(() => {throw 'Reached todo in the code'})()"]
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
              string.concat([
                // compile not implemented should probably be env/platform/browser
                "  return window.compile(",
                t.literal(usable),
                ", ast)",
              ]),
              "})",
            ]
            _ -> [
              "(() => {throw 'Failed to build provider for ", // We should just panic here
              // montyp_to_string(loader, state.native_to_string),
              "'})()",
            ]
          }
        _ -> todo("handle error from loader")
      }
    }
    // This type is recursive starts with generated ends up with nil, in the nil case We should never have a provider?
    e.Provider(_, _, generated) -> render(unsafe_coerce(generated), state)
  }
}

pub external fn unsafe_coerce(a) -> b =
  "../../eyg_utils.js" "identity"
