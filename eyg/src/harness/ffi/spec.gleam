import gleam/list
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import gleeunit/should

fn is_integer(term) {
  case term {
    r.Integer(x) -> Ok(x)
    _ -> Error(Nil)
  }
}

pub fn integer() {
  #(t.Integer, is_integer, r.Integer)
}

fn is_string(term) {
  case term {
    r.Binary(x) -> Ok(x)
    _ -> Error(Nil)
  }
}

pub fn string() {
  #(t.Binary, is_string, r.Binary)
}

pub fn is_list(term, cast) {
  case term {
    r.LinkedList(x) -> list.try_map(x, cast)
    _ -> Error(Nil)
  }
}

pub fn list_of(element) {
  let #(t, cast, encode) = element
  #(
    t.LinkedList(t),
    is_list(_, cast),
    fn(v) { r.LinkedList(list.map(v, encode)) },
  )
}

pub fn lambda(from, to) {
  let #(t1, cast, _) = from
  let #(t2, _, encode) = to
  // TODO ref
  let constraint = t.Fun(t1, t.Open(1), t2)

  #(
    constraint,
    fn(x) { todo("parse") },
    fn(impl) {
      r.Builtin(fn(arg, k) {
        assert Ok(input) = cast(arg)
        r.continue(k, encode(impl(input)))
      })
    },
  )
  // todo("foo")
}

pub fn build(spec, term) {
  let #(constraint, _, encode) = spec
  //   let call = fn(args) {, args) }
  #(constraint, encode(term))
}
