import gleam/io
import gleam/list
import language/ast.{
  Assignment, Binary, Call, Case, Destructure, Fn, Let, NewData, Row, RowPattern,
  Tuple, TuplePattern, Var,
}

pub fn int_to_string(int) {
  do_to_string(int)
}

if erlang {
  external fn do_to_string(Int) -> String =
    "erlang" "integer_to_binary"
}

if javascript {
  external fn do_to_string(Int) -> String =
    "../gleam_stdlib.js" "to_string"
}

fn map_first(list, func) {
  case list {
    [first, ..rest] -> [func(first), ..rest]
    _ -> todo("map first didn't do anything")
  }
}

fn map_last(list, func) {
  list
  |> list.reverse()
  |> map_first(func)
  |> list.reverse()
}

fn indent(lines) {
  list.map(lines, fn(line) { concat(["  ", line]) })
}

fn wrap(pre, lines, post) {
  case lines {
    [] -> {
      [concat([pre, post])]
    }
    _ ->
      lines
      |> map_first(fn(first) { concat([pre, first]) })
      |> map_last(fn(last) { concat([last, post]) })
  }
}

fn squash(a, b) {
  let [join, ..rest] = b
  map_last(a, fn(last) { concat([last, join]) })
  |> list.append(rest)
}

fn render_label(quantified_label) {
  let #(label, count) = quantified_label
  concat([label, "$", int_to_string(count)])
}

fn wrap_return(lines, in_tail) {
  case in_tail {
    True -> wrap("return ", lines, ";")
    False -> lines
  }
}

fn intersperse(list, delimeter) {
  case list {
    [] -> []
    [one, ..rest] -> do_intersperse(rest, delimeter, [one])
  }
}

fn do_intersperse(list, delimeter, accumulator) {
  case list {
    [] -> list.reverse(accumulator)
    [item, ..list] ->
      do_intersperse(list, delimeter, [item, delimeter, ..accumulator])
  }
}

fn strip_type(typed) {
  let #(_, tree) = typed
  tree
}

fn render_destructure(args) {
  list.map(args, render_label)
  |> fn(args) {
    case args {
      [] -> [""]
      args -> args
    }
  }
  |> intersperse(", ")
  |> wrap("[", _, "]")
  |> concat()
}

pub fn render(typed, in_tail) {
  case typed {
    #(_, NewData(type_name, params, constructors, in)) ->
      list.map(
        constructors,
        fn(constructor) {
          let #(label, arguments) = constructor
          // names are unique within the checked type
          let #(name, _) = label
          concat([
            "let ",
            render_label(label),
            " = ((...args) => Object.assign({ type: \"",
            name,
            "\" }, args));",
          ])
        },
      )
      |> list.append(render(in, in_tail))
    #(_, Let(pattern, value, in)) -> {
      let value = render(value, False)
      let value = case pattern {
        Assignment(label) -> {
          let assignment = concat(["let ", render_label(label), " = "])
          wrap(assignment, value, ";")
        }
        TuplePattern(assignments) -> {
          let assignment =
            concat(["let ", render_destructure(assignments), " = "])
          wrap(assignment, value, ";")
        }
        RowPattern(rows) -> {
          let assignment =
            list.map(
              rows,
              fn(row) {
                let #(row_name, label) = row
                concat([row_name, ": ", render_label(label)])
              },
            )
            |> intersperse(", ")
            |> wrap("{", _, "}")
            |> concat()
          let assignment = concat(["let ", assignment, " = "])
          wrap(assignment, value, ";")
        }
        Destructure(_name, args) -> {
          let assignment = concat(["let ", render_destructure(args), " = "])
          wrap(assignment, wrap("Object.values(", value, ")"), ";")
        }
      }
      list.append(value, render(in, in_tail))
    }
    #(_, Var(label)) -> wrap_return([render_label(label)], in_tail)
    #(_, Case(subject, clauses)) -> {
      let #(lines, _) =
        list.fold(
          clauses,
          #([], True),
          fn(clause, state) {
            let #(accumulator, first) = state
            let pre = case first {
              True -> "if"
              False -> "} else if"
            }
            let #(pattern, then) = clause
            let [l1, l2] = case pattern {
              Destructure(name, args) -> [
                concat([pre, " (subject.type == \"", name, "\") {"]),
                concat([
                  "  let ",
                  render_destructure(args),
                  " = Object.values(subject)",
                ]),
              ]
              Assignment(#(label, count)) -> [
                "} else {",
                concat(["  let ", label, " = subject;"]),
              ]
            }
            #(
              list.append(accumulator, [l1, l2, ..indent(render(then, True))]),
              False,
            )
          },
        )
      let lines =
        ["((subject) => {", ..lines]
        |> list.append(["}})"])
      let subject = wrap("(", render(subject, False), ")")
      squash(lines, subject)
      |> wrap_return(in_tail)
    }
    // TODO escape
    #(_, Binary(content)) ->
      wrap_return([concat(["\"", content, "\""])], in_tail)
    #(_, Tuple(values)) -> {
      // same mapping as in call
      let values = list.map(values, render(_, False))
      let values =
        list.map(
          values,
          fn(lines) {
            case lines {
              [single] -> single
              _ -> todo("multiple lines in constructing tuple")
            }
          },
        )
      let values_string =
        values
        |> intersperse(", ")
        |> wrap("[", _, "]")
        |> concat()
      wrap_return([values_string], in_tail)
    }
    #(_, Row(rows)) -> {
      let pairs =
        list.map(
          rows,
          fn(row) {
            let #(name, value) = row
            case render(value, False) {
              [single] -> concat([name, ":", single])
              _ -> todo("multiple lines in row construction arguments")
            }
          },
        )
      let pairs_string =
        pairs
        |> intersperse(", ")
        |> wrap("{", _, "}")
        |> concat()
      wrap_return([pairs_string], in_tail)
    }
    #(_, Fn(args, in)) -> {
      let args = list.map(args, strip_type)
      let args_string =
        list.map(args, render_label)
        |> intersperse(", ")
        // |> wrap("(", _, ")")
        |> concat()
      let start = concat(["((", args_string, ") => {"])
      case render(in, True) {
        [single] -> [concat([start, " ", single, " })"])]
        lines ->
          [start, ..indent(lines)]
          |> list.append(["})"])
      }
    }
    #(_, Call(function, with)) -> {
      let function = render(function, False)
      let with = list.map(with, render(_, False))
      let with =
        list.map(
          with,
          fn(lines) {
            case lines {
              [single] -> single
              _ -> todo("multiple lines in call arguments")
            }
          },
        )
      let args_string =
        with
        |> intersperse(", ")
        |> wrap("(", _, ")")
        |> concat()
      squash(function, [args_string])
      |> wrap_return(in_tail)
    }
  }
}

fn render_return(in_tail) {
  case in_tail {
    True -> "return "
    False -> ""
  }
}

if javascript {
  pub external fn concat(List(String)) -> String =
    "" "window.concatList"
}

if erlang {
  pub external fn concat(List(String)) -> String =
    "unicode" "characters_to_binary"
}
// external type Array(a)
// external fn array_concat(Array(String), String) -> String = "" "Array.prototype.join.call"
// external type A(a)
// external fn array(List(a)) -> A(a) = "helpers.js" "array"
// fn main() {
//   array([])
// }
