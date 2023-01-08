import gleam/list
import gleam/option.{None, Some}
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import gleam/javascript

fn is_integer(term) {
  case term {
    r.Integer(x) -> Ok(x)
    _ -> Error(Nil)
  }
}

pub fn integer() {
  fn(ref) { #(t.Integer, is_integer, r.Integer) }
}

fn is_string(term) {
  case term {
    r.Binary(x) -> Ok(x)
    _ -> Error(Nil)
  }
}

pub fn string() {
  fn(ref) { #(t.Binary, is_string, r.Binary) }
}

pub fn is_list(term, cast) {
  case term {
    r.LinkedList(x) -> list.try_map(x, cast)
    _ -> Error(Nil)
  }
}

pub fn list_of(element) {
  fn(ref) {
    let #(t, cast, encode) = element(ref)
    #(
      t.LinkedList(t),
      is_list(_, cast),
      fn(v) { r.LinkedList(list.map(v, encode)) },
    )
  }
}

pub fn empty() {
  fn(ref) { #(t.Closed, fn(x: Nil) { [] }) }
}

pub fn field(label, value, rest) {
  fn(ref) {
    let #(tvalue, _, encode_value) = value(ref)
    let #(ttail, encode_tail) = rest(ref)
    #(
      t.Extend(label, tvalue, ttail),
      fn(build) {
        let #(value, next) = build
        let fields = encode_tail(next)
        [#(label, encode_value(value)), ..fields]
      },
    )
  }
}

pub fn record(field_spec) {
  fn(ref) {
    let #(row, encode) = field_spec(ref)
    #(t.Record(row), fn(_) { todo }, fn(term) { r.Record(encode(term)) })
  }
}

pub fn end() {
  fn(ref) { #(t.Closed, fn(x: r.Term) { x }) }
}

pub fn variant(label, value, tail) {
  fn(ref) {
    let #(tvalue, _, encode_value) = value(ref)
    let #(ttail, encode_tail) = tail(ref)
    #(
      t.Extend(label, tvalue, ttail),
      fn(encode) {
        let inner = encode(fn(value) { r.Tagged(label, encode_value(value)) })
        encode_tail(inner)
      },
    )
  }
}

pub fn union(row_spec) {
  fn(ref) {
    let #(row, encode) = row_spec(ref)
    #(t.Union(row), fn(_) { todo }, fn(term) { encode(term) })
  }
}

pub fn lambda(from, to) {
  fn(ref) {
    let #(t1, cast, _) = from(ref)
    let #(t2, _, encode) = to(ref)
    let constraint =
      t.Fun(t1, t.Open(javascript.update_reference(ref, fn(x) { x + 1 })), t2)

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
  }
}

pub fn build(spec, term) {
  // ignored match is for fn arg terms, only needed within specific function contexts.
  // the builder starts with the encode side
  let #(constraint, _, encode) = spec(javascript.make_reference(0))
  #(constraint, encode(term))
}
