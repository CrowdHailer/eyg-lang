import eygir/expression as e
import gleam/bit_array
import gleam/dynamic.{
  DecodeError, any, decode1, decode2, decode3, field, int, string,
}
import gleam/json
import gleam/result

fn label() {
  any([field("label", string), field("l", string)])
}

fn base_encoded(value) {
  use encoded <- result.then(string(value))
  result.map_error(bit_array.base64_decode(encoded), fn(_) {
    [dynamic.DecodeError("base64 encoded", encoded, [""])]
  })
}

pub fn decoder(x) {
  use node <- result.then(any([field("node", string), field("0", string)])(x))
  case node {
    "v" | "variable" -> decode1(e.Variable, label())
    "f" | "function" ->
      decode2(
        e.Lambda,
        label(),
        any([field("body", decoder), field("b", decoder)]),
      )
    "a" | "call" ->
      decode2(
        e.Apply,
        any([field("function", decoder), field("f", decoder)]),
        any([field("arg", decoder), field("a", decoder)]),
      )
    "l" | "let" ->
      decode3(
        e.Let,
        label(),
        any([field("value", decoder), field("v", decoder)]),
        any([field("then", decoder), field("t", decoder)]),
      )
    "x" ->
      decode1(
        e.Binary,
        any([field("value", base_encoded), field("v", base_encoded)]),
      )

    "i" | "integer" ->
      decode1(e.Integer, any([field("value", int), field("v", int)]))
    "s" | "binary" ->
      decode1(e.Str, any([field("value", string), field("v", string)]))
    "ta" | "tail" -> fn(_) { Ok(e.Tail) }
    "c" | "cons" -> fn(_) { Ok(e.Cons) }
    "z" | "vacant" ->
      decode1(e.Vacant, any([field("c", string), fn(_) { Ok("no comment") }]))
    "u" | "empty" -> fn(_) { Ok(e.Empty) }
    "e" | "extend" -> decode1(e.Extend, label())
    "g" | "select" -> decode1(e.Select, label())
    "o" | "overwrite" -> decode1(e.Overwrite, label())
    "t" | "tag" -> decode1(e.Tag, label())
    "m" | "case" -> decode1(e.Case, label())
    "n" | "nocases" -> fn(_) { Ok(e.NoCases) }
    "p" | "perform" -> decode1(e.Perform, label())
    "h" | "handle" -> decode1(e.Handle, label())
    "hs" | "shallow" -> decode1(e.Shallow, label())
    "b" | "builtin" -> decode1(e.Builtin, label())

    incorrect -> fn(_) { Error([DecodeError("node", incorrect, ["0"])]) }
  }(x)
}

pub fn from_json(raw) {
  json.decode(raw, decoder)
}
