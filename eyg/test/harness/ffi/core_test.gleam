import eyg/analysis/inference
import eyg/analysis/typ as t
import eyg/runtime/capture
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eygir/annotated as a
import gleam/dict
import gleeunit/should
import harness/ffi/core.{expression_to_language}
import harness/stdlib

pub fn unequal_test() {
  let prog = a.apply(a.apply(a.builtin("equal"), a.integer(1)), a.integer(2))
  let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))

  inference.sound(sub)
  |> should.equal(Ok(Nil))

  inference.type_of(sub, [])
  |> should.equal(Ok(t.boolean))

  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.false))
}

pub fn equal_test() {
  let prog =
    a.apply(a.apply(a.builtin("equal"), a.string("foo")), a.string("foo"))
  let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))

  inference.sound(sub)
  |> should.equal(Ok(Nil))

  inference.type_of(sub, [])
  |> should.equal(Ok(t.boolean))

  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.true))
}

// also tests generalization of builtins
pub fn debug_test() {
  let prog =
    a.let_(
      "_",
      a.apply(a.builtin("debug"), a.integer(10)),
      a.apply(a.builtin("debug"), a.string("foo")),
    )
  let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))

  inference.sound(sub)
  |> should.equal(Ok(Nil))

  inference.type_of(sub, [])
  |> should.equal(Ok(t.Str))

  r.execute(prog, stdlib.env(), dict.new())
  // value is serialized as binary, hence the quotes
  |> should.equal(Ok(v.String("\"foo\"")))
}

pub fn simple_fix_test() {
  let prog = a.apply(a.builtin("fix"), a.lambda("_", a.string("foo")))
  let sub = inference.infer(dict.new(), prog, t.Unbound(-10), t.Closed)

  inference.sound(sub)
  |> should.equal(Ok(Nil))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Str))

  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.String("foo")))
}

pub fn no_recursive_fix_test() {
  let prog =
    a.let_(
      "fix",
      a.builtin("fix"),
      a.apply(
        a.apply(
          a.variable("fix"),
          a.lambda("_", a.lambda("x", a.variable("x"))),
        ),
        a.integer(1),
      ),
    )
  let sub = inference.infer(dict.new(), prog, t.Unbound(-10), t.Closed)

  inference.sound(sub)
  |> should.equal(Ok(Nil))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Integer))

  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Integer(1)))
}

pub fn recursive_sum_test() {
  let list =
    a.apply(
      a.apply(a.cons(), a.integer(1)),
      a.apply(a.apply(a.cons(), a.integer(3)), a.tail()),
    )

  let switch =
    a.apply(
      a.apply(
        a.case_("Ok"),
        a.lambda(
          "split",
          a.apply(
            a.apply(
              a.variable("self"),
              a.apply(
                a.apply(a.builtin("int_add"), a.variable("total")),
                a.apply(a.select("head"), a.variable("split")),
              ),
            ),
            a.apply(a.select("tail"), a.variable("split")),
          ),
        ),
      ),
      a.apply(
        a.apply(a.case_("Error"), a.lambda("_", a.variable("total"))),
        a.nocases(),
      ),
    )
  let sum =
    a.lambda(
      "self",
      a.lambda(
        "total",
        a.lambda(
          "items",
          a.apply(switch, a.apply(a.builtin("list_pop"), a.variable("items"))),
        ),
      ),
    )
  let prog =
    a.apply(a.apply(a.apply(a.builtin("fix"), sum), a.integer(0)), list)
  let sub = inference.infer(dict.new(), prog, t.Unbound(-10), t.Closed)

  inference.sound(sub)
  |> should.equal(Ok(Nil))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Integer))

  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Integer(4)))
}

pub fn eval_test() {
  let value = a.string("foo")

  let p =
    value
    |> expression_to_language()
    |> v.LinkedList()
    |> capture.capture(Nil)
  let prog = a.apply(a.builtin("eval"), p)
  // This is old style inference not JM
  // let sub = inference.infer(dict.new(), prog, t.Unbound(-1), t.Open(-2))

  // inference.sound(sub)
  // |> should.equal(Ok(Nil))

  // inference.type_of(sub, [])
  // |> should.equal(Ok(t.boolean))

  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Tagged("Ok", v.String("foo"))))
}

pub fn language_to_expression_test() {
  a.apply(a.variable("x"), a.integer(1))
  |> core.expression_to_language()
  |> core.language_to_expression()
  |> should.be_ok
}
