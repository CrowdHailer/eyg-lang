import gleam/io
import gleam/map
import gleam/set
import gleam/setx
import eygir/expression as e
import eyg/analysis/typ.{ftv} as t
import eyg/analysis/jm/type_
import eyg/analysis/env
import eyg/analysis/inference.{infer, type_of}
// top level analysis
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/unification
import gleeunit/should
import eyg/incremental/store
import eyg/analysis/jm/infer as jm
import eyg/analysis/jm/type_ as jmt
import eyg/analysis/jm/error as jm_error

pub fn resolve(inf: inference.Infered, typ) {
  unification.resolve(inf.substitutions, typ)
}

pub fn resolve_row(inf: inference.Infered, row) {
  unification.resolve_row(inf.substitutions, row)
}

pub fn resolve_effect(inf: inference.Infered, row) {
  unification.resolve_effect(inf.substitutions, row)
}

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

fn jm(exp, type_, eff) { 
  let #(root, store) = store.load(store.empty(), exp)

  let sub = map.new()
  let next = 0
  let env = map.new()
  let source = store.source
  let ref = root
  let types = map.new()

  let #(sub, _next, types) = jm.infer(sub, next, env, source, ref, type_, eff, types)
  case map.get(types, root) {
    Ok(Ok(t)) -> Ok(jmt.resolve(t, sub))
    Ok(Error(reason)) -> Error(reason)
    // DOes panic expression print message
    Error(_) -> {
      io.debug(root)
      io.debug(source |> map.to_list)
      io.debug(types |> map.to_list)
      todo("no typr")
    }
  }
}

// Primitive
pub fn binary_test() {
  let exp = e.Binary("hi")
  let env = env.empty()

  // exact type
  let typ = t.Binary
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  let assert Ok(t.Binary) = type_of(sub, [])

  // unbound type
  let typ = t.Unbound(-1)
  let sub = infer(env, exp, typ, eff)
  let assert t.Binary = resolve(sub, typ)
  let assert Ok(t.Binary) = type_of(sub, [])
  let assert Ok(type_.String) = jm(exp, type_.Var(-1), type_.Empty)

  // incorrect type
  let typ = t.Integer
  let sub = infer(env, exp, typ, eff)
  let assert Error(_) = type_of(sub, [])
  let assert Error(#(jm_error.TypeMismatch(jmt.Integer, jmt.String), jmt.Integer, jmt.String)) = jm(exp, type_.Integer, type_.Empty)
}

pub fn integer_test() {
  let exp = e.Integer(1)
  let env = env.empty()

  // exact type
  let typ = t.Integer
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  let assert Ok(t.Integer) = type_of(sub, [])

  // unbound type
  let typ = t.Unbound(-1)
  let sub = infer(env, exp, typ, eff)
  let assert t.Integer = resolve(sub, typ)
  let assert Ok(t.Integer) = type_of(sub, [])

  // incorrect type
  let typ = t.Binary
  let sub = infer(env, exp, typ, eff)
  let assert Error(_) = type_of(sub, [])
}

pub fn empty_list_test() {
  let exp = e.Tail
  let env = env.empty()

  // exact type
  let typ = t.LinkedList(t.Binary)
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  let assert Ok(t.LinkedList(t.Binary)) = type_of(sub, [])

  // unbound element
  let typ = t.LinkedList(t.Unbound(-1))
  let sub = infer(env, exp, typ, eff)

  let assert Ok(t.LinkedList(e)) = type_of(sub, [])
  resolve(sub, t.Unbound(-1))
  |> should.equal(e)

  // unbound type
  let typ = t.Unbound(1)
  let sub = infer(env, exp, typ, eff)

  let assert Ok(t.LinkedList(t.Unbound(_))) = type_of(sub, [])

  // incorrect type
  let typ = t.Binary
  let sub = infer(env, exp, typ, eff)
  let assert Error(_) = type_of(sub, [])
}

pub fn primitive_list_test() {
  let exp = e.Apply(e.Apply(e.Cons, e.Integer(0)), e.Tail)
  let env = env.empty()

  let typ = t.LinkedList(t.Binary)
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  let assert Ok(t.LinkedList(t.Binary)) = type_of(sub, [])
  let assert Ok(type_.LinkedList(type_.Integer)) = jm(exp, type_.Var(-1), type_.Empty)
  |> io.debug
  // THere is an error missing and the principle is wrong

  let assert Ok(t.Fun(t.LinkedList(t.Binary), t.Closed, t.LinkedList(t.Binary))) =
    type_of(sub, [0])
  let assert Ok(t.LinkedList(t.Binary)) = type_of(sub, [1])
  let assert Ok(t.Fun(
    t.Binary,
    t.Closed,
    t.Fun(t.LinkedList(t.Binary), t.Closed, t.LinkedList(t.Binary)),
  )) = type_of(sub, [0, 0])
  let assert Error(_) = type_of(sub, [0, 1])
}

// Variables
pub fn variables_test() {
  let exp = e.Let("x", e.Binary("hi"), e.Variable("x"))
  let env = env.empty()
  let typ = t.Binary
  let eff = t.Closed

  let _ = infer(env, exp, typ, eff)

  let typ = t.Unbound(1)
  let sub = infer(env, exp, typ, eff)
  let assert t.Binary = resolve(sub, typ)
  let assert Ok(t.Binary) = type_of(sub, [0])
  let assert Ok(t.Binary) = type_of(sub, [1])
}

// Functions
pub fn function_test() {
  let exp = e.Lambda("x", e.Binary("hi"))
  let env = env.empty()
  let typ = t.Fun(t.Integer, t.Closed, t.Binary)
  let eff = t.Closed

  let _ = infer(env, exp, typ, eff)

  let typ = t.Unbound(-1)
  let sub = infer(env, exp, typ, eff)
  let assert t.Fun(t.Unbound(_), t.Open(_), t.Binary) = resolve(sub, typ)
}

pub fn pure_function_test() {
  let exp = e.Lambda("x", e.Variable("x"))
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  let assert t.Fun(t.Unbound(x), t.Open(2), t.Unbound(y)) = resolve(sub, typ)
  should.equal(x, y)
  let assert Ok(t.Unbound(z)) = type_of(sub, [0])
  should.equal(x, z)
}

pub fn pure_function_call_test() {
  let func = e.Lambda("x", e.Variable("x"))
  let exp = e.Apply(func, e.Binary("hi"))
  let env = env.empty()
  let typ = t.Binary
  let eff = t.Closed

  let _ = infer(env, exp, typ, eff)

  let typ = t.Unbound(-1)
  let sub = infer(env, exp, typ, eff)
  let assert t.Binary = resolve(sub, typ)
}

// call generic could be a test row(a = id(Int) b = id(Int))

fn field(row: t.Row(a), label) {
  case row {
    t.Open(_) | t.Closed -> Error(Nil)
    t.Extend(l, t, _) if l == label -> Ok(t)
    t.Extend(_, _, tail) -> field(tail, label)
  }
}

// Records

pub fn select_test() {
  let exp = e.Select("foo")
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  let assert t.Fun(t.Record(t.Extend(l, a, t.Open(_))), _eff, b) =
    resolve(sub, typ)
  should.equal(a, b)
  should.equal(l, "foo")

  let exp = e.Apply(exp, e.Variable("x"))
  let env = env.empty()
  let x = Scheme([], t.Record(t.Extend("foo", t.Binary, t.Closed)))
  let env = map.insert(env, "x", x)

  let sub = infer(env, exp, typ, eff)

  let assert t.Binary = resolve(sub, typ)
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

  let sub = infer(env, exp, typ, eff)

  let assert t.Unbound(x) = resolve(sub, typ)
  let assert t.Record(row) = resolve(sub, t.Unbound(-2))
  let assert Ok(t.Unbound(y)) = field(row, "foo")
  should.not_equal(x, y)
  let assert Ok(t.Unbound(z)) = field(row, "bar")
  should.equal(x, z)
}

// Unions
pub fn tag_test() {
  let exp = e.Tag("foo")
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  let assert t.Fun(a, _eff, t.Union(t.Extend(l, b, t.Open(_)))) =
    resolve(sub, typ)
  should.equal(a, b)
  should.equal(l, "foo")

  let exp = e.Apply(exp, e.Binary("hi"))
  let sub = infer(env, exp, typ, eff)
  let assert t.Union(t.Extend(l, a, t.Open(_))) = resolve(sub, typ)
  should.equal(a, t.Binary)
  should.equal(l, "foo")
}

// Test raising effects in branches are matched

pub fn single_effect_test() {
  let exp = e.Perform("Log")
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Open(-2)

  let sub = infer(env, exp, typ, eff)
  // No effects untill called
  let assert t.Open(-2) = resolve_effect(sub, eff)
  let assert t.Fun(t.Unbound(arg), fn_eff, t.Unbound(ret)) = resolve(sub, typ)
  let assert Ok(#(t.Unbound(lift), t.Unbound(cont))) = field(fn_eff, "Log")
  should.not_equal(lift, cont)
  should.equal(arg, lift)
  should.equal(cont, ret)

  // test effects are raised when called
  let exp = e.Apply(exp, e.Binary("hi"))
  let typ = t.Integer
  let sub = infer(env, exp, typ, eff)
  let assert Ok(#(t.Binary, t.Integer)) =
    resolve_effect(sub, eff)
    |> field("Log")
}

pub fn collect_effects_test() {
  let exp = e.Apply(e.Perform("Log"), e.Apply(e.Perform("Ask"), e.Binary("hi")))
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Open(-2)

  let sub = infer(env, exp, typ, eff)
  let assert t.Unbound(final) = resolve(sub, typ)
  let raised = resolve_effect(sub, eff)
  let assert Ok(#(t.Binary, t.Unbound(ret1))) = field(raised, "Ask")
  let assert Ok(#(t.Unbound(lift2), t.Unbound(ret2))) = field(raised, "Log")
  should.equal(ret1, lift2)
  should.equal(ret2, final)
}

pub fn anony_test() {
  let exp =
    e.Apply(
      e.Lambda("f", e.Apply(e.Variable("f"), e.Binary("hi"))),
      e.Lambda("_", e.Integer(1)),
    )

  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  let assert t.Integer = resolve(sub, typ)
}

// Checks that a function is correctly generalized over it's effect type
pub fn instantiation_of_effect_test() {
  let source =
    e.Let(
      "f",
      e.Lambda("x", e.Variable("x")),
      e.Let(
        "do",
        e.Lambda(
          "x",
          e.Let(
            "_",
            e.Apply(e.Perform("Log"), e.Binary("my log")),
            e.Apply(e.Variable("f"), e.Integer(0)),
          ),
        ),
        e.Apply(e.Variable("f"), e.Empty),
      ),
    )
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed
  let sub = infer(env, source, typ, eff)
  let assert Ok(Nil) = inference.sound(sub)
}
