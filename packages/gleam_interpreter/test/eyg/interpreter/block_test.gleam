import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/option.{None, Some}

pub fn a_block_returns_its_value_and_scope_test() {
  let source = ir.let_("a", ir.integer(1), ir.variable("a"))
  let assert Ok(#(Some(v.Integer(1)), scope)) = block.execute(source, [])
  assert scope == [#("a", v.Integer(1))]
}

pub fn a_block_ending_in_a_let_has_no_value_test() {
  let source = ir.let_("a", ir.integer(1), ir.vacant())
  let assert Ok(#(None, scope)) = block.execute(source, [])
  assert scope == [#("a", v.Integer(1))]
}

pub fn an_empty_block_preserves_the_initial_scope_test() {
  let scope = [#("a", v.Integer(1))]
  assert block.execute(ir.vacant(), scope) == Ok(#(None, scope))
}

pub fn successive_blocks_preserve_bindings_and_shadowing_test() {
  let assert Ok(#(None, scope)) =
    block.execute(ir.let_("a", ir.integer(1), ir.vacant()), [])
  let assert Ok(#(Some(v.Integer(1)), scope)) =
    block.execute(ir.variable("a"), scope)
  let assert Ok(#(None, scope)) =
    block.execute(ir.let_("a", ir.integer(2), ir.vacant()), scope)
  assert scope == [#("a", v.Integer(2)), #("a", v.Integer(1))]
  assert block.execute(ir.variable("a"), scope)
    == Ok(#(Some(v.Integer(2)), scope))
}

pub fn a_closure_captures_only_user_bindings_test() {
  let source = ir.let_("a", ir.integer(1), ir.lambda("_", ir.variable("a")))
  let assert Ok(#(Some(v.Closure("_", _, captured)), scope)) =
    block.execute(source, [])
  assert captured == [#("a", v.Integer(1))]
  assert scope == captured
}

pub fn a_final_call_restores_the_callers_scope_test() {
  let source =
    ir.let_(
      "f",
      ir.lambda("a", ir.let_("local", ir.integer(3), ir.variable("a"))),
      ir.let_("a", ir.integer(1), ir.apply(ir.variable("f"), ir.integer(2))),
    )
  let assert Ok(#(Some(v.Integer(2)), [#("a", v.Integer(1)), #("f", _)])) =
    block.execute(source, [])
}

pub fn nested_let_bindings_do_not_escape_test() {
  let source =
    ir.let_(
      "a",
      ir.let_("local", ir.integer(1), ir.variable("local")),
      ir.apply(
        ir.let_(
          "callee",
          ir.lambda("x", ir.variable("x")),
          ir.variable("callee"),
        ),
        ir.let_("argument", ir.integer(2), ir.variable("argument")),
      ),
    )
  assert block.execute(source, [])
    == Ok(#(Some(v.Integer(2)), [#("a", v.Integer(1))]))
}

pub fn only_a_top_level_vacant_node_is_an_absent_value_test() {
  let assert Error(#(break.Vacant, _, _, _)) =
    block.execute(ir.let_("a", ir.vacant(), ir.integer(1)), [])
  let assert Error(#(break.Vacant, _, _, _)) =
    block.execute(ir.apply(ir.lambda("_", ir.vacant()), ir.unit()), [])
}

pub fn the_scope_is_the_blocks_after_an_effect_in_its_value_test() {
  let source =
    ir.let_("a", ir.integer(1), ir.apply(ir.perform("Ask"), ir.unit()))
  let assert Error(#(break.UnhandledEffect("Ask", _), _, env, k)) =
    block.execute(source, [])
  let assert Ok(#(Some(v.Integer(2)), scope)) =
    block.resume(v.Integer(2), env, k)
  assert scope == [#("a", v.Integer(1))]
}
