import gleam/list
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eygir/expression as e
import harness/ffi/spec.{
  build, empty, end, field, integer, lambda, list_of, record, string, unbound,
  union, variant,
}
import gleeunit/should

pub fn integer_test() {
  let #(spec, term) =
    integer()
    |> build(5)
  term
  |> should.equal(r.Integer(5))

  spec
  |> should.equal(t.Integer)
}

pub fn string_test() {
  let #(spec, term) =
    string()
    |> build("hello")
  term
  |> should.equal(r.Binary("hello"))

  spec
  |> should.equal(t.Binary)
}

// lambda pure function
pub fn lambda_test() {
  let #(spec, term) =
    lambda(integer(), integer())
    |> build(fn(x) { x + 1 })

  r.eval_call(term, r.Integer(2), fn(_, _) { todo("no provider") }, r.Value)
  |> should.equal(r.Value(r.Integer(3)))

  spec
  |> should.equal(t.Fun(t.Integer, t.Open(0), t.Integer))
}

pub fn nested_lambda_test() {
  let #(spec, term) =
    lambda(integer(), lambda(string(), integer()))
    |> build(fn(x) { fn(_b) { x + 1 } })

  r.eval_call(
    term,
    r.Integer(2),
    fn(_, _) { todo("no provider") },
    r.eval_call(_, r.Binary("hey"), fn(_, _) { todo("no provider") }, r.Value),
  )
  |> should.equal(r.Value(r.Integer(3)))

  spec
  |> should.equal(t.Fun(
    t.Integer,
    t.Open(1),
    t.Fun(t.Binary, t.Open(0), t.Integer),
  ))
}

pub fn unbound_test() {
  let #(spec, term) =
    unbound()
    |> build(r.Binary("anything"))
  should.equal(r.Binary("anything"), term)
  should.equal(t.Unbound(0), spec)
}

pub fn polymorphic_function_test() {
  let t = unbound()
  let #(spec, term) =
    lambda(t, t)
    |> build(fn(x) { x })
  r.eval_call(term, r.Binary("hey"), fn(_, _) { todo("no provider") }, r.Value)
  |> should.equal(r.Value(r.Binary("hey")))
  should.equal(t.Fun(t.Unbound(0), t.Open(1), t.Unbound(0)), spec)
}

pub fn first_class_function_test() {
  let t = unbound()
  let #(spec, term) =
    lambda(lambda(integer(), integer()), integer())
    |> build(fn(f) { f(5) })
  r.eval_call(
    term,
    r.Function("x", e.Variable("x"), [], []),
    fn(_, _) { todo("no provider") },
    r.Value,
  )
  |> should.equal(r.Value(r.Integer(5)))
  should.equal(
    t.Fun(t.Fun(t.Integer, t.Open(0), t.Integer), t.Open(1), t.Integer),
    spec,
  )
}

pub fn list_test() {
  let #(spec, term) =
    list_of(integer())
    |> build([1, 2])

  term
  |> should.equal(r.LinkedList([r.Integer(1), r.Integer(2)]))

  spec
  |> should.equal(t.LinkedList(t.Integer))
}

pub fn list_fn_test() {
  let #(spec, term) =
    lambda(list_of(integer()), integer())
    |> build(fn(x) { list.length(x) })

  r.eval_call(term, r.LinkedList([]), fn(_, _) { todo("no provider") }, r.Value)
  |> should.equal(r.Value(r.Integer(0)))

  spec
  |> should.equal(t.Fun(t.LinkedList(t.Integer), t.Open(0), t.Integer))
}

pub fn unit_type_test() {
  let #(spec, term) =
    record(empty())
    |> build(Nil)
  should.equal(spec, t.Record(t.Closed))
  should.equal(term, r.Record([]))
}

pub fn record_test() {
  let #(spec, term) =
    record(field("name", string(), field("age", integer(), empty())))
    |> build(#("bob", #(5, Nil)))
  should.equal(
    spec,
    t.Record(t.Extend("name", t.Binary, t.Extend("age", t.Integer, t.Closed))),
  )
  should.equal(
    term,
    r.Record([#("name", r.Binary("bob")), #("age", r.Integer(5))]),
  )
}

pub fn unit_fn_test() {
  let #(spec, term) =
    lambda(record(empty()), integer())
    |> build(fn(_: Nil) { 5 })

  r.eval_call(term, r.Record([]), fn(_, _) { todo("no provider") }, r.Value)
  |> should.equal(r.Value(r.Integer(5)))

  spec
  |> should.equal(t.Fun(t.Record(t.Closed), t.Open(0), t.Integer))
}

pub fn record_fn_test() {
  let #(spec, term) =
    lambda(
      record(field("name", string(), field("age", integer(), empty()))),
      integer(),
    )
    |> build(fn(rec) {
      let #(_name, #(age, Nil)) = rec
      age
    })

  r.eval_call(
    term,
    r.Record([#("age", r.Integer(55)), #("name", r.Binary("bob"))]),
    fn(_, _) { todo("no provider") },
    r.Value,
  )
  |> should.equal(r.Value(r.Integer(55)))

  spec
  |> should.equal(t.Fun(
    t.Record(t.Extend("name", t.Binary, t.Extend("age", t.Integer, t.Closed))),
    t.Open(0),
    t.Integer,
  ))
}

pub fn union_test() {
  let #(spec, term) =
    union(variant("Some", integer(), variant("None", integer(), end())))
    |> build(fn(some) { fn(_none) { some(10) } })
  should.equal(
    spec,
    t.Union(t.Extend("Some", t.Integer, t.Extend("None", t.Integer, t.Closed))),
  )
  should.equal(term, r.Tagged("Some", r.Integer(10)))
}
