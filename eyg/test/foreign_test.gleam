import gleam/dynamic
import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None, Some}
import gleam/set
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/spec.{
  build, empty, end, field, integer, lambda, list_of, record, string, union,
  variant,
}
import harness/ffi/integer
import harness/ffi/env
import eyg/analysis/inference
import eygir/expression as e
import gleeunit/should
import gleam/javascript

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

  r.eval_call(term, r.Integer(2), r.Value)
  |> should.equal(r.Value(r.Integer(3)))

  spec
  |> should.equal(t.Fun(t.Integer, t.Open(0), t.Integer))
}

pub fn nested_lambda_test() {
  let #(spec, term) =
    lambda(integer(), lambda(string(), integer()))
    |> build(fn(x) { fn(b) { x + 1 } })

  r.eval_call(term, r.Integer(2), r.eval_call(_, r.Binary("hey"), r.Value))
  |> should.equal(r.Value(r.Integer(3)))

  spec
  |> should.equal(t.Fun(
    t.Integer,
    t.Open(1),
    t.Fun(t.Binary, t.Open(0), t.Integer),
  ))
}

pub fn list_test() {
  // sum fn
  let #(spec, term) =
    list_of(integer())
    |> build([1, 2])

  term
  |> should.equal(r.LinkedList([r.Integer(1), r.Integer(2)]))

  spec
  |> should.equal(t.LinkedList(t.Integer))
}

pub fn list_fn_test() {
  // sum fn
  let #(spec, term) =
    lambda(list_of(integer()), integer())
    |> build(fn(x) { list.length(x) })

  r.eval_call(term, r.LinkedList([]), r.Value)
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

pub fn union_test() {
  let #(spec, term) =
    union(variant("Some", integer(), variant("None", integer(), end())))
    |> build(fn(some) { fn(none) { some(10) } })
  should.equal(
    spec,
    t.Union(t.Extend("Some", t.Integer, t.Extend("None", t.Integer, t.Closed))),
  )
  should.equal(term, r.Tagged("Some", r.Integer(10)))
}

// unbound -> id
// unbound -> list.reverse

pub fn add_test() {
  let #(types, values) =
    env.init()
    |> env.extend("ffi_add", integer.add())

  let prog = e.Apply(e.Apply(e.Variable("ffi_add"), e.Integer(1)), e.Integer(2))
  let sub = inference.infer(types, prog, t.Unbound(-1), t.Open(-2))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Integer))
  r.eval(prog, values, r.Value)
  |> should.equal(r.Value(r.Integer(3)))
}
