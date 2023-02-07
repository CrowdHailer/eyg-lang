import gleam/dynamic
import gleam/json
import magpie/store/in_memory.{B, I, L, S, Triple}

fn dump_value(value) {
  case value {
    B(b) -> json.object([#("b", json.bool(b))])
    I(i) -> json.object([#("i", json.int(i))])
    S(s) -> json.object([#("s", json.string(s))])
    L(l) -> json.object([#("l", json.array(l, dump_value))])
  }
}

fn dump_triple(t: Triple) {
  json.array([json.int(t.0), json.string(t.1), dump_value(t.2)], fn(x) { x })
}

fn value() {
  fn(x) {
    dynamic.any([
      dynamic.decode1(B, dynamic.field("b", dynamic.bool)),
      dynamic.decode1(I, dynamic.field("i", dynamic.int)),
      dynamic.decode1(S, dynamic.field("s", dynamic.string)),
      dynamic.decode1(L, dynamic.field("l", dynamic.list(value()))),
    ])(
      x,
    )
  }
}

fn decoder() {
  dynamic.list(dynamic.tuple3(dynamic.int, dynamic.string, value()))
}

pub fn from_string(string) {
  json.decode(string, decoder())
}

pub fn to_string(triples) {
  json.to_string(json.array(triples, dump_triple))
}
