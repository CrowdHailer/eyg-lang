import gleam/io
import gleam/int
import gleam/list
import gleam/string
import eyg/ast/expression.{
  Binary, Call, Case, Constructor, Expression, Function, Let, Name, Provider, Row,
  Tuple, Variable,
}
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer/polytype.{State}
import eyg/typer
import eyg/codegen/utilities.{
  indent, squash, wrap_lines, wrap_single_or_multiline,
}

pub fn maybe_wrap_expression(expression, state) {
  case expression {
    #(_, Let(_, _, _)) | #(_, Name(_, _)) -> {
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

pub fn render(tree: Expression(typer.Metadata), state) {
  let #(context, tree) = tree
  case tree {
    // TODO escape
    Binary(content) -> wrap_return([string.join(["\"", content, "\""])], state)
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
        pattern.Discard -> {
          // Don't add any labelled variables into scope
          // let state = with_assignment(label, state)
          let assignment = string.join(["let ", "_", " = "])
          #(wrap_lines(assignment, value, ";"), state)
        }
        pattern.Variable(label) -> {
          let state = with_assignment(label, state)
          let assignment =
            string.join(["let ", render_label(label, state), " = "])
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
            |> string.join()
          let assignment = string.join(["let ", destructure, " = "])
          #(wrap_lines(assignment, value, ";"), state)
        }
        pattern.Row(fields) -> {
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
          let destructure =
            fields
            |> list.intersperse(", ")
            // wrap_lines not a good name here
            |> wrap_lines("{", _, "}")
            |> string.join()
          let assignment = string.join(["let ", destructure, " = "])
          #(wrap_lines(assignment, value, ";"), state)
        }
      }
      list.append(assignment, render(then, state))
    }
    Variable(label) -> wrap_return([render_label(label, state)], state)
    Function(pattern.Tuple(for), body) -> {
      // assert  = for
      let #(for, state) =
        list.map_state(
          for,
          state,
          fn(label, state) {
            let state = with_assignment(label, state)
            #(render_label(label, state), state)
          },
        )
      let args_string =
        for
        |> list.intersperse(", ")
        |> string.join()
      let start = string.join(["(function self(", args_string, ") {"])
      case render(body, in_tail(True, state)) {
        [single] -> [string.join([start, " ", single, " })"])]
        lines ->
          [start, ..indent(lines)]
          |> list.append(["})"])
      }
      |> wrap_return(state)
    }
    Function(pattern.Row(_), body) -> // todo
    ["TODO"]
    Call(function, #(_, Tuple(with))) -> {
      let function = render(function, in_tail(False, state))
      let with = list.map(with, maybe_wrap_expression(_, state))
      let args_string = wrap_single_or_multiline(with, ",", "(", ")")
      squash(function, args_string)
      |> wrap_return(state)
    }
    Call(function, #(_, Row(with))) -> ["Big row todo"]

    Name(_name, then) -> render(then, state)
    Constructor(_named, variant) -> [
      // ...inner working on assuption ALWAYS called with tuple
      string.join([
        "(function (...inner) { return {variant: \"",
        variant,
        "\", inner} })",
      ]),
    ]
    Case(_name, subject, clauses) -> {
      let clauses =
        list.map(
          clauses,
          fn(clause) {
            let #(
              variant,
              "$",
              #(_, Let(pattern.Tuple(_assigns), #(_, Variable("$")), _)) as then,
            ) = clause
            // Using render here relies on a variable of $ not being set
            let [first, ..rest] = render(then, in_tail(True, state))
            [string.join(["case \"", variant, "\": ", first]), ..indent(rest)]
          },
        )
      // could use subject and subject.inner in arbitrary let statements
      let switch =
        ["(({variant, inner: $}) => { switch (variant) {"]
        |> list.append(indent(list.flatten(clauses)))
        |> list.append(["}})"])
      let subject = wrap_lines("(", maybe_wrap_expression(subject, state), ")")
      squash(switch, subject)
      |> wrap_return(state)
    }
    Provider(config, func) -> {
      let typer.Metadata(type_: Ok(expected), ..) = context
      let #(a, b, typer) = state
      let State(substitutions: substitutions, ..) = typer
      let expected = monotype.resolve(expected, substitutions)
      let tree = func(config, expected)
      case typer.infer(tree, expected, typer) {
        #(typed, typer) -> render(typed, state)
        _ -> todo("could not infer")
      }
    }
  }
}
