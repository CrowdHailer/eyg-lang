import gleam/dynamic
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import gleeunit/should

pub fn int() {
  #(
    t.Integer,
    dynamic.int,
    fn(v, args) {
      assert [] = args
      r.Integer(v)
    },
  )
}

pub fn string() {
  #(
    t.Binary,
    dynamic.string,
    fn(v, args) {
      assert [] = args
      r.Binary(v)
    },
  )
}

pub fn lambda(from, to) {
  let #(t1, cast, _) = from
  let #(t2, _, encode) = to
  // TODO ref
  let constraint = t.Fun(t1, t.Open(1), t2)
  let call = fn(args) { todo }

  #(
    constraint,
    fn(x) { todo("parse") },
    fn(term, args) {
      let [input, ..rest] = args
      assert Ok(input) = cast(input)
      encode(term(input), rest)
    },
  )
}

pub fn build(spec, term) {
  let #(constraint, _, encode) = spec
  let call = fn(args) { encode(term, args) }
  #(constraint, call)
}

pub fn integer_test() {
  let #(spec, f) =
    int()
    |> build(5)
  f([])
  |> should.equal(r.Integer(5))

  spec
  |> should.equal(t.Integer)
}

pub fn string_test() {
  let #(spec, f) =
    string()
    |> build("hello")
  f([])
  |> should.equal(r.Binary("hello"))

  spec
  |> should.equal(t.Binary)
}

// lambda pure function
pub fn lambda_test() {
  let #(spec, f) =
    lambda(int(), int())
    |> build(fn(x) { x + 1 })

  f([dynamic.from(2)])
  |> should.equal(r.Integer(3))

  spec
  |> should.equal(t.Fun(t.Integer, t.Open(1), t.Integer))
}

pub fn nested_lambda_test() {
  let #(spec, f) =
    lambda(int(), lambda(string(), int()))
    |> build(fn(x) { fn(b) { x + 1 } })

  f([dynamic.from(2), dynamic.from("hey")])
  |> should.equal(r.Integer(3))

  spec
  |> should.equal(t.Fun(
    t.Integer,
    t.Open(1),
    t.Fun(t.Binary, t.Open(1), t.Integer),
  ))
}
// This works for constraints in i.e. make constrains for the editor and get back resulting fn
