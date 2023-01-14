import gleam/json.{array, int, null, object, string}
import eygir/expression as e

fn node(name, attributes) {
  object([#("node", string(name)), ..attributes])
}

fn label(value) {
  #("label", string(value))
}

pub fn encode(exp) {
  case exp {
    e.Variable(x) -> node("variable", [label(x)])
    e.Lambda(x, body) -> node("function", [label(x), #("body", encode(body))])
    e.Apply(func, arg) ->
      node("call", [#("function", encode(func)), #("arg", encode(arg))])
    e.Let(x, value, then) ->
      [label(x), #("value", encode(value)), #("then", encode(then))]
      |> node("let", _)
    e.Integer(i) -> node("integer", [#("value", int(i))])
    e.Binary(s) -> node("binary", [#("value", string(s))])
    e.Tail -> node("tail", [])
    e.Cons -> node("cons", [])
    e.Vacant -> node("vacant", [])
    e.Record(_, _) -> todo("remove heres")
    e.Empty -> node("empty", [])
    e.Extend(x) -> node("extend", [label(x)])
    e.Select(x) -> node("select", [label(x)])
    e.Overwrite(x) -> node("overwrite", [label(x)])
    e.Tag(x) -> node("tag", [label(x)])
    e.Case(x) -> node("case", [label(x)])
    e.NoCases -> node("nocases", [])
    e.Match(_, _) -> todo("remove match")
    e.Deep(_, _) -> todo("remove deep")
    e.Perform(x) -> node("perform", [label(x)])
    e.Handle(x) -> node("handle", [label(x)])
  }
}

pub fn to_json(exp) -> String {
  json.to_string(encode(exp))
}
