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

pub fn render(typed) {
  case typed {
    #(_, Let(pattern, value, in)) -> [
      concat(["let ", render_pattern(pattern), " = ", iife(value), ";"]),
      ..render(in)
    ]
    #(_, Var(#(label, count))) -> [concat([label, "$", int_to_string(count)])]
    // TODO escape
    #(_, Binary(content)) -> [concat(["\"", content, "\""])]
    #(_, Fn(args, _)) -> {
      let args_string = list.map(args, fn(quantified_label) {
        let #(label, count) = quantified_label
        concat([label, "$", int_to_string(count), ", "])
      })
      |> concat()
      [args_string]
    }
    #(_, Call(function, with)) -> {
      let [last, ..previous] = list.reverse(render(function))

      let args_string = list.map(with, render)
      |> list.fold([], fn(argument, previous) {
        case argument {
          [single] ->  [", ", single, ..previous] 
        }
      })
      |> list.reverse()
      |> concat()

      let last = concat([last, "(", args_string, ")"])
      list.reverse([last, ..previous])
    }
  }
}

fn render_pattern(pattern) {
  case pattern {
    Assignment(#(label, count)) -> concat([label, "$", int_to_string(count)])
    Destructure(_name, args) -> {
      let arg_string =
        list.map(
          args,
          fn(arg) {
            let #(name, count) = arg
            concat([name, "$", int_to_string(count), ", "])
          },
        )
        |> concat()
      concat(["[", arg_string, "]"])
    }
  }
}

// rust has wrap_expression for maybe iife
// let v$1 = v$0
// let v$2 = "hello"
// let v$3 = function(arg$1, arg$2) { don't need to wrap }
// let v$4 = (($subject) => {
// Needs to handle nested subjectes in cases or maybe not because v$3 will still be in scope
// })(v$3)
// fn concat(list, separator) {
//   array_concat(array(list), separator)
// }
// return lines then indent in parent
fn iife(term) {
  case render(term) {
    [single] -> single
  }
  //   concat(["(() => { \n", "TODO term", "\n})()"])
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
