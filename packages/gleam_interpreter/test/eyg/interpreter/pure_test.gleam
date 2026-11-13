import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/ir/tree as ir

pub fn pure_preserves_closure_and_capture_test() {
  let source =
    ir.lambda(
      "x",
      ir.call(ir.builtin("int_add"), [
        ir.variable("n"),
        ir.variable("x"),
      ]),
    )
  let assert Ok(function) = expression.execute(source, [#("n", v.Integer(1))])
  let assert Ok(unchanged) =
    expression.call(v.Partial(v.Builtin("pure"), []), [#(function, Nil)])
  assert unchanged == v.Partial(v.Pure, [function])
  assert expression.call(unchanged, [#(v.Integer(41), Nil)])
    == Ok(v.Integer(42))
}

pub fn pure_accepts_partial_builtins_test() {
  let source =
    ir.call(ir.builtin("pure"), [
      ir.apply(ir.builtin("int_add"), ir.integer(1)),
      ir.integer(41),
    ])
  assert expression.execute(source, []) == Ok(v.Integer(42))
}

pub fn pure_rejects_non_functions_test() {
  let source = ir.apply(ir.builtin("pure"), ir.integer(41))
  let assert Error(#(break.IncorrectTerm("Function", v.Integer(41)), _, _, _)) =
    expression.execute(source, [])
}

pub fn unchecked_pure_blocks_escaping_effects_test() {
  let source =
    ir.call(ir.builtin("pure"), [
      ir.lambda("x", ir.apply(ir.perform("Log"), ir.variable("x"))),
      ir.integer(41),
    ])
  let assert Error(#(break.ImpureEffect("Log", v.Integer(41)), _, _, _)) =
    expression.execute(source, [])
}
