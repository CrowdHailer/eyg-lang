import gleam/json.{int, object, string}
import eygir/expression as e

fn node(name, attributes) {
  object([#("0", string(name)), ..attributes])
}

fn label(value) {
  #("l", string(value))
}

pub fn encode(exp) {
  case exp {
    e.Variable(x) -> node("v", [label(x)])
    // function
    e.Lambda(x, body) -> node("f", [label(x), #("b", encode(body))])
    e.Apply(func, arg) -> node("a", [#("f", encode(func)), #("a", encode(arg))])
    e.Let(x, value, then) ->
      [label(x), #("v", encode(value)), #("t", encode(then))]
      |> node("l", _)
    e.Integer(i) -> node("i", [#("v", int(i))])
    // string
    e.Binary(s) -> node("s", [#("v", string(s))])
    e.Tail -> node("ta", [])
    e.Cons -> node("c", [])
    // zero
    e.Vacant(comment) -> node("z", [#("c", string(comment))])
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
  }
}

pub fn to_json(exp) -> String {
  json.to_string(encode(exp))
}
