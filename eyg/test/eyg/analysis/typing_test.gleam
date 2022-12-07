import gleam/io
import gleam/map
import gleam/option
import gleam/set
import gleam/setx
import eyg/analysis/expression as e
import eyg/analysis/typ.{ftv} as t
import eyg/analysis/env
import eyg/analysis/infer.{infer}
// top level analysis
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/unification.{resolve}
import gleam/javascript
import gleeunit/should

pub fn free_type_variables_test() {
  ftv(t.Unbound(0))
  |> should.equal(setx.singleton(t.Term(0)))

  ftv(t.Binary)
  |> should.equal(set.new())

  ftv(t.Integer)
  |> should.equal(set.new())

  ftv(t.Fun(t.Integer, t.Closed, t.Integer))
  |> should.equal(set.new())

  ftv(t.Fun(t.Unbound(1), t.Closed, t.Unbound(1)))
  |> should.equal(setx.singleton(t.Term(1)))

  // rows
  ftv(t.Record(t.Closed))
  |> should.equal(set.new())

  ftv(t.Union(t.Closed))
  |> should.equal(set.new())

  let row = t.Extend("r", t.Unbound(1), t.Extend("s", t.Unbound(2), t.Open(3)))
  ftv(t.Record(row))
  |> should.equal(set.from_list([t.Term(1), t.Term(2), t.Row(3)]))

  // effects
  let eff = t.Extend("r", #(t.Unbound(1), t.Unbound(2)), t.Open(3))
  ftv(t.Fun(t.Integer, eff, t.Integer))
  |> should.equal(set.from_list([t.Term(1), t.Term(2), t.Effect(3)]))
}

// Primitive
pub fn binary_test() {
  let exp = e.Binary
  let env = env.empty()
  let typ = t.Binary
  let eff = t.Closed
  let ref = javascript.make_reference(0)

  let _ = infer(env, exp, typ, eff, ref)

  let typ = t.Unbound(1)
  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Binary = resolve(sub, typ)
}

pub fn integer_test() {
  let exp = e.Integer
  let env = env.empty()
  let typ = t.Integer
  let eff = t.Closed
  let ref = javascript.make_reference(0)

  let _ = infer(env, exp, typ, eff, ref)

  let typ = t.Unbound(1)
  let ref = javascript.make_reference(0)

  let sub = infer(env, exp, typ, eff, ref)
  assert t.Integer = resolve(sub, typ)
}

// Variables
pub fn variables_test() {
  let exp = e.Let("x", e.Binary, e.Variable("x"))
  let env = env.empty()
  let typ = t.Binary
  let eff = t.Closed
  let ref = javascript.make_reference(0)

  let _ = infer(env, exp, typ, eff, ref)

  let typ = t.Unbound(1)
  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Binary = resolve(sub, typ)
}

// let x = x is an error

// Functions
pub fn function_test() {
  let exp = e.Lambda("x", e.Binary)
  let env = env.empty()
  let typ = t.Fun(t.Integer, t.Closed, t.Binary)
  let eff = t.Closed

  let ref = javascript.make_reference(0)
  let _ = infer(env, exp, typ, eff, ref)

  let typ = t.Unbound(-1)
  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Fun(t.Unbound(_), t.Open(_), t.Binary) = resolve(sub, typ)
}

pub fn pure_function_test() {
  let exp = e.Lambda("x", e.Variable("x"))
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Fun(t.Unbound(x), t.Open(2), t.Unbound(y)) = resolve(sub, typ)
  assert True = x == y
}

pub fn pure_function_call_test() {
  let func = e.Lambda("x", e.Variable("x"))
  let exp = e.Apply(func, e.Binary)
  let env = env.empty()
  let typ = t.Binary
  let eff = t.Closed

  let ref = javascript.make_reference(0)
  let _ = infer(env, exp, typ, eff, ref)

  let typ = t.Unbound(-1)
  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Binary = resolve(sub, typ)
}

// call generic could be a test row(a = id(Int) b = id(Int))

fn field(row, label) {
  case row {
    t.Open(_) | t.Closed -> Error(Nil)
    t.Extend(l, t, _) if l == label -> Ok(t)
    t.Extend(_, _, tail) -> field(tail, label)
  }
}

// Records
pub fn record_creation_test() {
  let exp = e.Record([], option.None)
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Record(row) = resolve(sub, typ)
  should.equal(row, t.Closed)

  let exp = e.Record([#("foo", e.Binary), #("bar", e.Integer)], option.None)
  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Record(row) = resolve(sub, typ)
  assert t.Extend(
    label: "bar",
    value: t.Integer,
    tail: t.Extend(label: "foo", value: t.Binary, tail: t.Closed),
  ) = row
}

pub fn record_update_test() {
  let exp = e.Record([], option.Some("x"))
  let env = env.empty()
  let x = Scheme([], t.Unbound(-2))
  let env = map.insert(env, "x", x)
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Record(row) = resolve(sub, typ)
  assert t.Open(x) = row
  assert t.Record(row) = resolve(sub, t.Unbound(-2))
  assert t.Open(y) = row
  should.equal(x, y)

  let exp = e.Record([#("foo", e.Binary)], option.Some("x"))
  let env = env.empty()
  let mono =
    t.Record(t.Extend("foo", t.Binary, t.Extend("bar", t.Integer, t.Closed)))
  let x = Scheme([], mono)
  let env = map.insert(env, "x", x)
  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Record(row) = resolve(sub, typ)
  assert t.Extend(
    label: "foo",
    value: t.Binary,
    tail: t.Extend(label: "bar", value: t.Integer, tail: t.Closed),
  ) = row
}

// TODO update type
// pub fn record_update_type_test() {
//   let exp = e.Record([#("foo", e.Binary)], option.Some("x"))
//   let env = env.empty()
//   let mono =
//     t.Record(t.Extend("foo", t.Integer, t.Extend("bar", t.Integer, t.Closed)))
//   let x = Scheme([], mono)
//   let env = map.insert(env, "x", x)
//   let typ = t.Unbound(-1)
//   let eff = t.Closed

//   let ref = javascript.make_reference(0)
//   let sub = infer(env, exp, typ, eff, ref)
//   assert t.Record(row) = resolve(sub, typ)
//   assert t.Extend(
//     label: "foo",
//     value: t.Binary,
//     tail: t.Extend(label: "bar", value: t.Integer, tail: t.Closed),
//   ) = row
// }

pub fn select_test() {
  let exp = e.Select("foo")
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Fun(t.Record(t.Extend(l, a, t.Open(_))), _eff, b) = resolve(sub, typ)
  should.equal(a, b)
  should.equal(l, "foo")

  let exp = e.Apply(exp, e.Variable("x"))
  let env = env.empty()
  let x = Scheme([], t.Record(t.Extend("foo", t.Binary, t.Closed)))
  let env = map.insert(env, "x", x)

  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)

  assert t.Binary = resolve(sub, typ)
}

pub fn combine_select_test() {
  let exp =
    e.Let(
      "_",
      e.Apply(e.Select("foo"), e.Variable("x")),
      e.Apply(e.Select("bar"), e.Variable("x")),
    )
  let env = env.empty()
  let x = Scheme([], t.Unbound(-2))
  let env = map.insert(env, "x", x)
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)

  assert t.Unbound(x) = resolve(sub, typ)
  assert t.Record(row) = resolve(sub, t.Unbound(-2))
  assert Ok(t.Unbound(y)) = field(row, "foo")
  should.not_equal(x, y)
  assert Ok(t.Unbound(z)) = field(row, "bar")
  should.equal(x, z)
}

// Unions
pub fn tag_test() {
  let exp = e.Tag("foo")
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Fun(a, _eff, t.Union(t.Extend(l, b, t.Open(_)))) = resolve(sub, typ)
  should.equal(a, b)
  should.equal(l, "foo")

  let exp = e.Apply(exp, e.Binary)
  let ref = javascript.make_reference(0)
  let sub = infer(env, exp, typ, eff, ref)
  assert t.Union(t.Extend(l, a, t.Open(_))) = resolve(sub, typ)
  should.equal(a, t.Binary)
  should.equal(l, "foo")
}
// Collect effects
// effects in functions
// infer apply where func &arg create effect and final application
