import gleam/dict
import eyg/analysis/typ as t
import eyg/analysis/inference
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eyg/runtime/capture
import eygir/expression as e
import eygir/annotated as e2
import harness/stdlib
import harness/ffi/core.{expression_to_language}
import gleeunit/should

pub fn unequal_test() {
  let prog = e.Apply(e.Apply(e.Builtin("equal"), e.Integer(1)), e.Integer(2))
  let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))

  inference.sound(sub)
  |> should.equal(Ok(Nil))

  inference.type_of(sub, [])
  |> should.equal(Ok(t.boolean))

  let prog = e2.add_meta(prog, Nil)
  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.false))
}

pub fn equal_test() {
  let prog = e.Apply(e.Apply(e.Builtin("equal"), e.Str("foo")), e.Str("foo"))
  let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))

  inference.sound(sub)
  |> should.equal(Ok(Nil))

  inference.type_of(sub, [])
  |> should.equal(Ok(t.boolean))

  let prog = e2.add_meta(prog, Nil)
  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.true))
}

// also tests generalization of builtins
pub fn debug_test() {
  let prog =
    e.Let(
      "_",
      e.Apply(e.Builtin("debug"), e.Integer(10)),
      e.Apply(e.Builtin("debug"), e.Str("foo")),
    )
  let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))

  inference.sound(sub)
  |> should.equal(Ok(Nil))

  inference.type_of(sub, [])
  |> should.equal(Ok(t.Str))

  let prog = e2.add_meta(prog, Nil)
  r.execute(prog, stdlib.env(), dict.new())
  // value is serialized as binary, hence the quotes
  |> should.equal(Ok(v.Str("\"foo\"")))
}

pub fn simple_fix_test() {
  let prog = e.Apply(e.Builtin("fix"), e.Lambda("_", e.Str("foo")))
  let sub = inference.infer(dict.new(), prog, t.Unbound(-10), t.Closed)

  inference.sound(sub)
  |> should.equal(Ok(Nil))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Str))

  let prog = e2.add_meta(prog, Nil)
  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Str("foo")))
}

pub fn no_recursive_fix_test() {
  let prog =
    e.Let(
      "fix",
      e.Builtin("fix"),
      e.Apply(
        e.Apply(
          e.Variable("fix"),
          e.Lambda("_", e.Lambda("x", e.Variable("x"))),
        ),
        e.Integer(1),
      ),
    )
  let sub = inference.infer(dict.new(), prog, t.Unbound(-10), t.Closed)

  inference.sound(sub)
  |> should.equal(Ok(Nil))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Integer))

  let prog = e2.add_meta(prog, Nil)
  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Integer(1)))
}

pub fn recursive_sum_test() {
  let list =
    e.Apply(
      e.Apply(e.Cons, e.Integer(1)),
      e.Apply(e.Apply(e.Cons, e.Integer(3)), e.Tail),
    )

  let switch =
    e.Apply(
      e.Apply(
        e.Case("Ok"),
        e.Lambda(
          "split",
          e.Apply(
            e.Apply(
              e.Variable("self"),
              e.Apply(
                e.Apply(e.Builtin("int_add"), e.Variable("total")),
                e.Apply(e.Select("head"), e.Variable("split")),
              ),
            ),
            e.Apply(e.Select("tail"), e.Variable("split")),
          ),
        ),
      ),
      e.Apply(
        e.Apply(e.Case("Error"), e.Lambda("_", e.Variable("total"))),
        e.NoCases,
      ),
    )
  let sum =
    e.Lambda(
      "self",
      e.Lambda(
        "total",
        e.Lambda(
          "items",
          e.Apply(switch, e.Apply(e.Builtin("list_pop"), e.Variable("items"))),
        ),
      ),
    )
  let prog =
    e.Apply(e.Apply(e.Apply(e.Builtin("fix"), sum), e.Integer(0)), list)
  let sub = inference.infer(dict.new(), prog, t.Unbound(-10), t.Closed)

  inference.sound(sub)
  |> should.equal(Ok(Nil))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Integer))

  let prog = e2.add_meta(prog, Nil)
  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Integer(4)))
}

pub fn eval_test() {
  let value = e.Str("foo")
  let value = e2.add_meta(value, Nil)

  let prog =
    value
    |> expression_to_language()
    |> v.LinkedList()
    |> capture.capture()
    |> e.Apply(e.Builtin("eval"), _)
  // This is old style inference not JM
  // let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))

  // inference.sound(sub)
  // |> should.equal(Ok(Nil))

  // inference.type_of(sub, [])
  // |> should.equal(Ok(t.boolean))

  let prog = e2.add_meta(prog, Nil)
  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Tagged("Ok", v.Str("foo"))))
}

pub fn language_to_expression_test() {
  e.Apply(e.Variable("x"), e.Integer(1))
  |> e2.add_meta(Nil)
  |> core.expression_to_language()
  |> core.language_to_expression()
  |> should.be_ok
  |> should.equal(e2.add_meta(e.Apply(e.Variable("x"), e.Integer(1)), Nil))
}
