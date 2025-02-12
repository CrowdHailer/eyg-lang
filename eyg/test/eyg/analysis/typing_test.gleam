import eyg/analysis/env
import eyg/analysis/inference.{infer, type_of}
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/typ.{ftv} as t
import eyg/analysis/unification
import eygir/annotated as a
import gleam/dict
import gleam/set
import gleam/setx
import gleeunit/should

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

  ftv(t.Str)
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
  let exp = a.string("hi")
  let env = env.empty()

  // exact type
  let typ = t.Str
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  let assert Ok(t.Str) = type_of(sub, [])

  // unbound type
  let typ = t.Unbound(-1)
  let sub = infer(env, exp, typ, eff)
  let assert t.Str = resolve(sub, typ)
  let assert Ok(t.Str) = type_of(sub, [])

  // incorrect type
  let typ = t.Integer
  let sub = infer(env, exp, typ, eff)
  let assert Error(_) = type_of(sub, [])
}

pub fn integer_test() {
  let exp = a.integer(1)
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
  let typ = t.Str
  let sub = infer(env, exp, typ, eff)
  let assert Error(_) = type_of(sub, [])
}

pub fn empty_list_test() {
  let exp = a.tail()
  let env = env.empty()

  // exact type
  let typ = t.LinkedList(t.Str)
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  let assert Ok(t.LinkedList(t.Str)) = type_of(sub, [])

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
  let typ = t.Str
  let sub = infer(env, exp, typ, eff)
  let assert Error(_) = type_of(sub, [])
}

pub fn primitive_list_test() {
  let exp = a.apply(a.apply(a.cons(), a.integer(0)), a.tail())
  let env = env.empty()

  let typ = t.LinkedList(t.Str)
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  let assert Ok(t.LinkedList(t.Str)) = type_of(sub, [])
  let assert Ok(t.Fun(t.LinkedList(t.Str), t.Closed, t.LinkedList(t.Str))) =
    type_of(sub, [0])
  let assert Ok(t.LinkedList(t.Str)) = type_of(sub, [1])
  let assert Ok(t.Fun(
    t.Str,
    t.Closed,
    t.Fun(t.LinkedList(t.Str), t.Closed, t.LinkedList(t.Str)),
  )) = type_of(sub, [0, 0])
  let assert Error(_) = type_of(sub, [0, 1])
}

// Variables
pub fn variables_test() {
  let exp = a.let_("x", a.string("hi"), a.variable("x"))
  let env = env.empty()
  let typ = t.Str
  let eff = t.Closed

  let _ = infer(env, exp, typ, eff)

  let typ = t.Unbound(1)
  let sub = infer(env, exp, typ, eff)
  let assert t.Str = resolve(sub, typ)
  let assert Ok(t.Str) = type_of(sub, [0])
  let assert Ok(t.Str) = type_of(sub, [1])
}

// Functions
pub fn function_test() {
  let exp = a.lambda("x", a.string("hi"))
  let env = env.empty()
  let typ = t.Fun(t.Integer, t.Closed, t.Str)
  let eff = t.Closed

  let _ = infer(env, exp, typ, eff)

  let typ = t.Unbound(-1)
  let sub = infer(env, exp, typ, eff)
  let assert t.Fun(t.Unbound(_), t.Open(_), t.Str) = resolve(sub, typ)
}

pub fn pure_function_test() {
  let exp = a.lambda("x", a.variable("x"))
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
  let func = a.lambda("x", a.variable("x"))
  let exp = a.apply(func, a.string("hi"))
  let env = env.empty()
  let typ = t.Str
  let eff = t.Closed

  let _ = infer(env, exp, typ, eff)

  let typ = t.Unbound(-1)
  let sub = infer(env, exp, typ, eff)
  let assert t.Str = resolve(sub, typ)
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
  let exp = a.select("foo")
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  let assert t.Fun(t.Record(t.Extend(l, a, t.Open(_))), _eff, b) =
    resolve(sub, typ)
  should.equal(a, b)
  should.equal(l, "foo")

  let exp = a.apply(exp, a.variable("x"))
  let env = env.empty()
  let x = Scheme([], t.Record(t.Extend("foo", t.Str, t.Closed)))
  let env = dict.insert(env, "x", x)

  let sub = infer(env, exp, typ, eff)

  let assert t.Str = resolve(sub, typ)
}

pub fn combine_select_test() {
  let exp =
    a.let_(
      "_",
      a.apply(a.select("foo"), a.variable("x")),
      a.apply(a.select("bar"), a.variable("x")),
    )
  let env = env.empty()
  let x = Scheme([], t.Unbound(-2))
  let env = dict.insert(env, "x", x)
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
  let exp = a.tag("foo")
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  let assert t.Fun(a, _eff, t.Union(t.Extend(l, b, t.Open(_)))) =
    resolve(sub, typ)
  should.equal(a, b)
  should.equal(l, "foo")

  let exp = a.apply(exp, a.string("hi"))
  let sub = infer(env, exp, typ, eff)
  let assert t.Union(t.Extend(l, a, t.Open(_))) = resolve(sub, typ)
  should.equal(a, t.Str)
  should.equal(l, "foo")
}

// Test raising effects in branches are matched

pub fn single_effect_test() {
  let exp = a.perform("Log")
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
  let exp = a.apply(exp, a.string("hi"))
  let typ = t.Integer
  let sub = infer(env, exp, typ, eff)
  let assert Ok(#(t.Str, t.Integer)) =
    resolve_effect(sub, eff)
    |> field("Log")
}

pub fn collect_effects_test() {
  let exp = a.apply(a.perform("Log"), a.apply(a.perform("Ask"), a.string("hi")))
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Open(-2)

  let sub = infer(env, exp, typ, eff)
  let assert t.Unbound(final) = resolve(sub, typ)
  let raised = resolve_effect(sub, eff)
  let assert Ok(#(t.Str, t.Unbound(ret1))) = field(raised, "Ask")
  let assert Ok(#(t.Unbound(lift2), t.Unbound(ret2))) = field(raised, "Log")
  should.equal(ret1, lift2)
  should.equal(ret2, final)
}

pub fn anony_test() {
  let exp =
    a.apply(
      a.lambda("f", a.apply(a.variable("f"), a.string("hi"))),
      a.lambda("_", a.integer(1)),
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
    a.let_(
      "f",
      a.lambda("x", a.variable("x")),
      a.let_(
        "do",
        a.lambda(
          "x",
          a.let_(
            "_",
            a.apply(a.perform("Log"), a.string("my log")),
            a.apply(a.variable("f"), a.integer(0)),
          ),
        ),
        a.apply(a.variable("f"), a.empty()),
      ),
    )
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed
  let sub = infer(env, source, typ, eff)
  let assert Ok(Nil) = inference.sound(sub)
}
