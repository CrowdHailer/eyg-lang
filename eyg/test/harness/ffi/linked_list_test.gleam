import eyg/ir/tree as ir
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import gleam/dict
import gleeunit/should
import harness/stdlib

pub fn fold_test() {
  let list =
    ir.apply(
      ir.apply(ir.cons(), ir.string("fizz")),
      ir.apply(ir.apply(ir.cons(), ir.string("buzz")), ir.tail()),
    )
  let reducer =
    ir.lambda(
      "element",
      ir.lambda(
        "state",
        ir.apply(
          ir.apply(ir.builtin("string_append"), ir.variable("state")),
          ir.variable("element"),
        ),
      ),
    )
  let source =
    ir.apply(
      ir.apply(ir.apply(ir.builtin("list_fold"), list), ir.string("initial")),
      reducer,
    )

  r.execute(source, stdlib.env(), dict.new())
  |> should.equal(Ok(v.String("initialfizzbuzz")))
}
