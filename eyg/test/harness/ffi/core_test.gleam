import eyg/analysis/inference
import eyg/analysis/typ as t
import eyg/ir/tree as ir
import eyg/runtime/capture
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import gleam/dict
import gleeunit/should
import harness/ffi/core.{expression_to_language}
import harness/stdlib

pub fn unequal_test() {
  let prog =
    ir.apply(ir.apply(ir.builtin("equal"), ir.integer(1)), ir.integer(2))
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
    ir.apply(ir.apply(ir.builtin("equal"), ir.string("foo")), ir.string("foo"))
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
    ir.let_(
      "_",
      ir.apply(ir.builtin("debug"), ir.integer(10)),
      ir.apply(ir.builtin("debug"), ir.string("foo")),
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
  let prog = ir.apply(ir.builtin("fix"), ir.lambda("_", ir.string("foo")))
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
    ir.let_(
      "fix",
      ir.builtin("fix"),
      ir.apply(
        ir.apply(
          ir.variable("fix"),
          ir.lambda("_", ir.lambda("x", ir.variable("x"))),
        ),
        ir.integer(1),
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
    ir.apply(
      ir.apply(ir.cons(), ir.integer(1)),
      ir.apply(ir.apply(ir.cons(), ir.integer(3)), ir.tail()),
    )

  let switch =
    ir.apply(
      ir.apply(
        ir.case_("Ok"),
        ir.lambda(
          "split",
          ir.apply(
            ir.apply(
              ir.variable("self"),
              ir.apply(
                ir.apply(ir.builtin("int_add"), ir.variable("total")),
                ir.apply(ir.select("head"), ir.variable("split")),
              ),
            ),
            ir.apply(ir.select("tail"), ir.variable("split")),
          ),
        ),
      ),
      ir.apply(
        ir.apply(ir.case_("Error"), ir.lambda("_", ir.variable("total"))),
        ir.nocases(),
      ),
    )
  let sum =
    ir.lambda(
      "self",
      ir.lambda(
        "total",
        ir.lambda(
          "items",
          ir.apply(
            switch,
            ir.apply(ir.builtin("list_pop"), ir.variable("items")),
          ),
        ),
      ),
    )
  let prog =
    ir.apply(ir.apply(ir.apply(ir.builtin("fix"), sum), ir.integer(0)), list)
  let sub = inference.infer(dict.new(), prog, t.Unbound(-10), t.Closed)

  inference.sound(sub)
  |> should.equal(Ok(Nil))
  inference.type_of(sub, [])
  |> should.equal(Ok(t.Integer))

  r.execute(prog, stdlib.env(), dict.new())
  |> should.equal(Ok(v.Integer(4)))
}

pub fn eval_test() {
  let value = ir.string("foo")

  let p =
    value
    |> expression_to_language()
    |> v.LinkedList()
    |> capture.capture(Nil)
  let prog = ir.apply(ir.builtin("eval"), p)
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
  ir.apply(ir.variable("x"), ir.integer(1))
  |> core.expression_to_language()
  |> core.language_to_expression()
  |> should.be_ok
}
