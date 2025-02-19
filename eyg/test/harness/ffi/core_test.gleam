import eyg/analysis/inference
import eyg/analysis/typ as t
import eyg/interpreter/expression as r
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/runtime/capture
import gleam/dict
import gleeunit/should
import harness/ffi/core.{expression_to_language}
import harness/stdlib

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

// factorial
// Debug should be an effect because we don't want different behaviour for different implementations
// {"0":"a","a":{"0":"i","v":6},"f":{"0":"a","a":{"0":"f","b":{"0":"f","b":{"0":"a","a":{"0":"a","a":{"0":"i","v":0},"f":{"0":"a","a":{"0":"v","l":"n"},"f":{"0":"b","l":"int_compare"}}},"f":{"0":"a","a":{"0":"f","b":{"0":"i","v":1},"l":"_"},"f":{"0":"a","a":{"0":"f","b":{"0":"a","a":{"0":"a","a":{"0":"a","a":{"0":"i","v":1},"f":{"0":"a","a":{"0":"v","l":"n"},"f":{"0":"b","l":"int_subtract"}}},"f":{"0":"v","l":"fact"}},"f":{"0":"a","a":{"0":"v","l":"n"},"f":{"0":"b","l":"int_multiply"}}},"l":"_"},"f":{"0":"m","l":"Gt"}}}},"l":"n"},"l":"fact"},"f":{"0":"b","l":"fix"}}}
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
