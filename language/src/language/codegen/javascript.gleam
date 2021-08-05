import gleam/io
import gleam/list
import language/ast.{Assignment, Binary, Call, Case, Destructure, Fn, Let, Var}

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
  let [first, ..rest] = list
  [func(first), ..rest]
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
  lines
  |> map_first(fn(first) { concat([pre, first]) })
  |> map_last(fn(last) { concat([last, post]) })
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
    #(_, Let(pattern, value, in)) -> {
      let value = render(value, False)
      let value = case pattern {
        Assignment(label) -> {
          let assignment = concat(["let ", render_label(label), " = "])
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
            let [single] = lines
            single
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
  external fn log(a) -> Nil =
    "" "console.log"

  external fn concat(List(String), String) -> String =
    "" "window.concatList"
}

if erlang {
  external fn concat(List(String)) -> String =
    "unicode" "characters_to_binary"
}
// external type Array(a)
// external fn array_concat(Array(String), String) -> String = "" "Array.prototype.join.call"
// external type A(a)
// external fn array(List(a)) -> A(a) = "helpers.js" "array"
// fn main() {
//   array([])
// }
