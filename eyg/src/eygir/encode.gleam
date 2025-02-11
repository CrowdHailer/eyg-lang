import eygir/annotated as e
import gleam/bit_array
import gleam/json.{int, object, string}

fn node(name, attributes) {
  object([#("0", string(name)), ..attributes])
}

fn label(value) {
  #("l", string(value))
}

fn bytes(b) {
  string(bit_array.base64_encode(b, True))
}

pub fn encode(tree) {
  let #(exp, _meta) = tree
  case exp {
    e.Variable(x) -> node("v", [label(x)])
    // function
    e.Lambda(x, body) -> node("f", [label(x), #("b", encode(body))])
    e.Apply(func, arg) -> node("a", [#("f", encode(func)), #("a", encode(arg))])
    e.Let(x, value, then) ->
      [label(x), #("v", encode(value)), #("t", encode(then))]
      |> node("l", _)
    // b already taken when adding binary
    e.Binary(b) -> node("x", [#("v", bytes(b))])
    e.Integer(i) -> node("i", [#("v", int(i))])
    // string
    e.Str(s) -> node("s", [#("v", string(s))])
    e.Tail -> node("ta", [])
    e.Cons -> node("c", [])
    // zero
    e.Vacant -> node("z", [])
    // unit
    e.Empty -> node("u", [])
    e.Extend(x) -> node("e", [label(x)])
    // get
    e.Select(x) -> node("g", [label(x)])
    e.Overwrite(x) -> node("o", [label(x)])
    e.Tag(x) -> node("t", [label(x)])
    // match
    e.Case(x) -> node("m", [label(x)])
    e.NoCases -> node("n", [])
    e.Perform(x) -> node("p", [label(x)])
    e.Handle(x) -> node("h", [label(x)])
    e.Builtin(x) -> node("b", [label(x)])
    e.Reference(x) -> node("#", [label(x)])
    e.NamedReference(p, r) -> node("@", [#("p", string(p)), #("r", int(r))])
  }
}

pub fn to_json(exp) -> String {
  json.to_string(encode(exp))
}
