import gleam/io
import gleam/map
import gleam/option.{None, Some}
import gleam/set
import gleam/setx
import eygir/expression as e
import eyg/analysis/typ.{ftv} as t
import eyg/analysis/env
import eyg/analysis/inference.{infer, type_of}
// top level analysis
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/unification
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
  let exp = e.Binary("hi")
  let env = env.empty()

  // exact type
  let typ = t.Binary
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  assert Ok(t.Binary) = type_of(sub, [])

  // unbound type
  let typ = t.Unbound(-1)
  let sub = infer(env, exp, typ, eff)
  assert t.Binary = resolve(sub, typ)
  assert Ok(t.Binary) = type_of(sub, [])

  // incorrect type
  let typ = t.Integer
  let sub = infer(env, exp, typ, eff)
  assert Error(_) = type_of(sub, [])
}

pub fn integer_test() {
  let exp = e.Integer(1)
  let env = env.empty()

  // exact type
  let typ = t.Integer
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  assert Ok(t.Integer) = type_of(sub, [])

  // unbound type
  let typ = t.Unbound(-1)
  let sub = infer(env, exp, typ, eff)
  assert t.Integer = resolve(sub, typ)
  assert Ok(t.Integer) = type_of(sub, [])

  // incorrect type
  let typ = t.Binary
  let sub = infer(env, exp, typ, eff)
  assert Error(_) = type_of(sub, [])
}

pub fn empty_list_test() {
  let exp = e.Tail
  let env = env.empty()

  // exact type
  let typ = t.LinkedList(t.Binary)
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  assert Ok(t.LinkedList(t.Binary)) = type_of(sub, [])

  // unbound element
  let typ = t.LinkedList(t.Unbound(-1))
  let sub = infer(env, exp, typ, eff)

  assert Ok(t.LinkedList(e)) = type_of(sub, [])
  resolve(sub, t.Unbound(-1))
  |> should.equal(e)

  // unbound type
  let typ = t.Unbound(1)
  let sub = infer(env, exp, typ, eff)

  assert Ok(t.LinkedList(t.Unbound(_))) = type_of(sub, [])

  // incorrect type
  let typ = t.Binary
  let sub = infer(env, exp, typ, eff)
  assert Error(_) = type_of(sub, [])
}

pub fn primitive_list_test() {
  let exp = e.Apply(e.Apply(e.Cons, e.Integer(0)), e.Tail)
  let env = env.empty()

  let typ = t.LinkedList(t.Binary)
  let eff = t.Closed
  let sub = infer(env, exp, typ, eff)
  assert Ok(t.LinkedList(t.Binary)) = type_of(sub, [])
  assert Ok(t.Fun(t.LinkedList(t.Binary), t.Closed, t.LinkedList(t.Binary))) =
    type_of(sub, [0])
  assert Ok(t.LinkedList(t.Binary)) = type_of(sub, [1])
  assert Ok(t.Fun(
    t.Binary,
    t.Closed,
    t.Fun(t.LinkedList(t.Binary), t.Closed, t.LinkedList(t.Binary)),
  )) = type_of(sub, [0, 0])
  assert Error(_) = type_of(sub, [0, 1])
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
  assert t.Binary = resolve(sub, typ)
  assert Ok(t.Binary) = type_of(sub, [0])
  assert Ok(t.Binary) = type_of(sub, [1])
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
  assert t.Fun(t.Unbound(_), t.Open(_), t.Binary) = resolve(sub, typ)
}

pub fn pure_function_test() {
  let exp = e.Lambda("x", e.Variable("x"))
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  assert t.Fun(t.Unbound(x), t.Open(2), t.Unbound(y)) = resolve(sub, typ)
  should.equal(x, y)
  assert Ok(t.Unbound(z)) = type_of(sub, [0])
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
  assert t.Binary = resolve(sub, typ)
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
pub fn record_creation_test() {
  let exp = e.Record([], option.None)
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  assert t.Record(row) = resolve(sub, typ)
  should.equal(row, t.Closed)

  let exp =
    e.Record([#("foo", e.Binary("hi")), #("bar", e.Integer(1))], option.None)
  let sub = infer(env, exp, typ, eff)
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

  let sub = infer(env, exp, typ, eff)
  assert t.Record(row) = resolve(sub, typ)
  assert t.Open(x) = row
  assert t.Record(row) = resolve(sub, t.Unbound(-2))
  assert t.Open(y) = row
  should.equal(x, y)

  let exp = e.Record([#("foo", e.Binary("hi"))], option.Some("x"))
  let env = env.empty()
  let mono =
    t.Record(t.Extend("foo", t.Binary, t.Extend("bar", t.Integer, t.Closed)))
  let x = Scheme([], mono)
  let env = map.insert(env, "x", x)
  let sub = infer(env, exp, typ, eff)
  assert t.Record(row) = resolve(sub, typ)
  assert t.Extend(
    label: "foo",
    value: t.Binary,
    tail: t.Extend(label: "bar", value: t.Integer, tail: t.Closed),
  ) = row
}

pub fn record_update_type_test() {
  let exp = e.Record([#("foo", e.Binary("hi"))], option.Some("x"))
  let env = env.empty()
  let mono =
    t.Record(t.Extend("foo", t.Integer, t.Extend("bar", t.Integer, t.Closed)))
  let x = Scheme([], mono)
  let env = map.insert(env, "x", x)
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  assert t.Record(row) = resolve(sub, typ)
  assert t.Extend(
    label: "foo",
    value: t.Binary,
    tail: t.Extend(label: "bar", value: t.Integer, tail: t.Closed),
  ) = row
}

pub fn select_test() {
  let exp = e.Select("foo")
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  assert t.Fun(t.Record(t.Extend(l, a, t.Open(_))), _eff, b) = resolve(sub, typ)
  should.equal(a, b)
  should.equal(l, "foo")

  let exp = e.Apply(exp, e.Variable("x"))
  let env = env.empty()
  let x = Scheme([], t.Record(t.Extend("foo", t.Binary, t.Closed)))
  let env = map.insert(env, "x", x)

  let sub = infer(env, exp, typ, eff)

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

  let sub = infer(env, exp, typ, eff)

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

  let sub = infer(env, exp, typ, eff)
  assert t.Fun(a, _eff, t.Union(t.Extend(l, b, t.Open(_)))) = resolve(sub, typ)
  should.equal(a, b)
  should.equal(l, "foo")

  let exp = e.Apply(exp, e.Binary("hi"))
  let sub = infer(env, exp, typ, eff)
  assert t.Union(t.Extend(l, a, t.Open(_))) = resolve(sub, typ)
  should.equal(a, t.Binary)
  should.equal(l, "foo")
}

// empty match is an error
pub fn closed_match_test() {
  let branches = [
    #("Some", "v", e.Variable("v")),
    #("None", "", e.Binary("hi")),
  ]
  let exp = e.Match(branches, None)
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  assert t.Fun(union, _, t.Binary) = resolve(sub, typ)
  assert t.Union(t.Extend(
    label: "Some",
    value: t.Binary,
    tail: t.Extend(label: "None", value: t.Unbound(_), tail: t.Closed),
  )) = union
}

pub fn open_match_test() {
  let branches = [
    #("Some", "v", e.Variable("v")),
    #("None", "", e.Binary("hi")),
  ]
  let exp = e.Match(branches, Some(#("", e.Binary("hi"))))
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed

  let sub = infer(env, exp, typ, eff)
  assert t.Fun(union, _, t.Binary) = resolve(sub, typ)
  assert t.Union(t.Extend(
    label: "Some",
    value: t.Binary,
    tail: t.Extend(label: "None", value: t.Unbound(_), tail: t.Open(_)),
  )) = union
}

// Test raising effects in branches are matched

pub fn single_effect_test() {
  let exp = e.Perform("Log")
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Open(-2)

  let sub = infer(env, exp, typ, eff)
  // No effects untill called
  assert t.Open(-2) = resolve_effect(sub, eff)
  assert t.Fun(t.Unbound(arg), fn_eff, t.Unbound(ret)) = resolve(sub, typ)
  assert Ok(#(t.Unbound(lift), t.Unbound(cont))) = field(fn_eff, "Log")
  should.not_equal(lift, cont)
  should.equal(arg, lift)
  should.equal(cont, ret)

  // test effects are raised when called
  let exp = e.Apply(exp, e.Binary("hi"))
  let typ = t.Integer
  let sub = infer(env, exp, typ, eff)
  assert Ok(#(t.Binary, t.Integer)) =
    resolve_effect(sub, eff)
    |> field("Log")
}

pub fn collect_effects_test() {
  let exp = e.Apply(e.Perform("Log"), e.Apply(e.Perform("Ask"), e.Binary("hi")))
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Open(-2)

  let sub = infer(env, exp, typ, eff)
  assert t.Unbound(final) = resolve(sub, typ)
  let raised = resolve_effect(sub, eff)
  assert Ok(#(t.Binary, t.Unbound(ret1))) = field(raised, "Ask")
  assert Ok(#(t.Unbound(lift2), t.Unbound(ret2))) = field(raised, "Log")
  should.equal(ret1, lift2)
  should.equal(ret2, final)
}

pub fn deep_handler_test() {
  // Put new, k -> k(new, 0)
  let then = e.Apply(e.Apply(e.Variable("k"), e.Variable("new")), e.Integer(1))
  let exp = e.Deep("state", [#("Put", "new", "k", then)])
  // We make the state the same as the raised value
  // I think exec & comp is a good set of naming.
  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Open(-2)

  let sub = infer(env, exp, typ, eff)
  assert t.Open(e0) = resolve_effect(sub, eff)
  assert t.Fun(t.Unbound(state1), t.Open(e1), exec) = resolve(sub, typ)
  should.not_equal(e0, e1)
  assert t.Fun(comp, t.Open(e2), t.Unbound(ret1)) = exec
  should.not_equal(e0, e2)
  should.not_equal(e1, e2)
  assert t.Fun(t.Record(t.Closed), inner, t.Unbound(ret2)) = comp
  // we have chosen to not need a pure handler part of the expression,
  // maybe needed if pure handler raises other effects
  should.equal(ret1, ret2)
  assert t.Extend("Put", #(t.Unbound(call), reply), t.Open(tail)) = inner
  // Put save the call value in state
  should.equal(call, state1)
  should.equal(reply, t.Integer)
  // calling the exec function with comp as an argument have all the uncaugt effects plus inner ones
  should.equal(e2, tail)
  // call with binary make state binary
  // call comp with perform last makes int return value
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
  assert t.Integer = resolve(sub, typ)
}

pub fn eval_handled_test() {
  let then =
    e.Apply(e.Apply(e.Variable("k"), e.Variable("state")), e.Variable("state"))
  let handler = e.Deep("state", [#("Get", "_", "k", then)])
  let comp = e.Lambda("_", e.Apply(e.Perform("Get"), e.Binary("hi")))
  let exp = e.Apply(e.Apply(handler, e.Integer(1)), comp)

  let env = env.empty()
  let typ = t.Unbound(-1)
  let eff = t.Closed
  let sub = infer(env, comp, typ, eff)
  assert _ = resolve(sub, typ)
  let sub = infer(env, e.Apply(handler, e.Integer(1)), typ, eff)
  assert _ = resolve(sub, typ)
  let sub = infer(env, exp, typ, eff)
  assert t.Integer = resolve(sub, typ)
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
  assert Ok(Nil) = inference.sound(sub)
}
// path + errors + warnings + alg w + gleam use + fixpoint + equi/iso + external lookup + hash + cbor + zipper
// interpreter + provider + cps codegen + pull out node for editor
// 1. interprest new expression, entrypoint and css
// 2. codegen new cps style for reactive front end
// + quote for universal apps
// 2.5. universal app log in front and backend some standard runtime choices
// 3. parser or editor
// can we do composable runtimes to work with effects
// path + errors + warnings +
// fixpoint + equi/iso (not needed array as native type)
// external lookup i.e. no mod of tree + hash + zipper ast.{Node}
// understand how to separate param without value from hash to value.
// Need this for walk through programming
// ui for all open var's
// interpreter + provider (provider not needed for current deploys)
// quote and provide are opposites
// cps codegen, not needed with interpreter tho probably in client
// editor render in solid js or just run through proper transform
// loader + quote instead of compile
// interpreter in my language -> implements a cps codegen using quote (Good steps)

// let {} = do("Log")("message")
// 1 + 2
// let {} = do("Log")("message")
// 3 + 4

// ((_) => {
//   return effect("Log", "message")
// })({}) => {
//   1 + 2
//   return effect("Log", "message")
// })({} => {

// })

// compile abtract effect types using generators
// quote and fix just in environment
// understand why fix is not as efficient as let rec

// Reactive style code from solid style

// path -> hash
// can we have hash even in parts referencing named vars?
// Is it always ok we debrujin
// hash -> type + evald
// uuid for views
