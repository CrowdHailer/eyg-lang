import language/ast.{Assignment, Binary, Call, Case, Destructure, Fn, Let, Var}

pub fn render(typed) {
  case typed {
    #(_, Let(Assignment(label), value, in)) -> [
      concat(["let ", label, " = ", iife(value), ";"]),
      ..render(in),
    ]
    #(_, Var(name)) -> [name]
    // TODO escape
    #(_, Binary(content)) -> [concat(["\"", content, "\""])]
    #(_, Fn(args, _)) -> [concat(["return (", "func", ")"])]
    #(_, Call(_, _)) -> ["return call"]
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
