import gleam/io
import gleam/string
import eyg/interpreter/interpreter as r

pub fn builtin() {
  [
    #("append", r.BuiltinFn(string_append)),
    #("uppercase", r.BuiltinFn(string_uppercase)),
    #("lowercase", r.BuiltinFn(string_lowercase)),
    #("replace", r.BuiltinFn(string_replace)),
  ]
  // These could be parts of the server environment only because they are encoded
  // Thi creates a circular dependency
  // #("js", r.BuiltinFn(runtime.render_object)),
}

external fn log(a) -> Nil =
  "" "console.log"

// This might well be easier to write in JS
pub fn compiled_string_append(args) {
  let #(first, second) = args
  string.append(first, second)
}

// interpreted
fn string_append(args) {
  case args {
    r.Tuple([r.Binary(first), r.Binary(second)]) ->
      Ok(r.Binary(string.append(first, second)))
    _ -> Error("bad arguments!!")
  }
}

fn string_uppercase(arg) {
  case arg {
    r.Binary(value) -> Ok(r.Binary(string.uppercase(value)))
    _ -> Error("bad arguments")
  }
}

fn string_lowercase(arg) {
  case arg {
    r.Binary(value) -> Ok(r.Binary(string.lowercase(value)))
    _ -> Error("bad arguments")
  }
}

fn string_replace(arg) {
  case arg {
    r.Tuple([r.Binary(string), r.Binary(target), r.Binary(replacement)]) ->
      Ok(r.Binary(string.replace(string, target, replacement)))
    _ -> Error("bad arguments")
  }
}

// std
const true = r.Tagged("True", r.Tuple([]))

const false = r.Tagged("False", r.Tuple([]))

pub fn equal(object) {
  assert r.Tuple([left, right]) = object
  Ok(case left == right {
    True -> true
    False -> false
  })
}
