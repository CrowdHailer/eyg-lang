import eyg/embed/run.{Crashed, Refused}
import eyg/interpreter/break
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/javascript/promise
import gleam/option.{None, Some}

// Count every effect and answer `Ask` with the count so far.
fn count(total, label, _lift) {
  case label {
    "Ask" -> Ok(#(total + 1, v.Integer(total + 1)))
    _ -> Error("no " <> label)
  }
}

fn ask() {
  ir.apply(ir.perform("Ask"), ir.unit())
}

pub fn effects_are_answered_by_the_handler_test() {
  let source = ir.add(ask(), ask())
  let #(total, result) = run.expression(source, [], 0, count, run.no_references)
  assert total == 2
  assert result == Ok(v.Integer(3))
}

pub fn a_refused_effect_stops_the_program_test() {
  let source = ir.let_("_", ask(), ir.apply(ir.perform("Launch"), ir.unit()))
  let #(total, result) = run.expression(source, [], 0, count, run.no_references)
  assert total == 1
  assert result == Error(Refused("Launch", "no Launch"))
}

pub fn references_are_resolved_by_the_host_test() {
  let resolve = fn(reference) {
    case reference {
      ir.Package("five") -> Ok(v.Integer(5))
      _ -> Error(Nil)
    }
  }
  let source = ir.add(ir.package("five"), ir.integer(1))
  assert run.expression(source, [], 0, count, resolve) == #(0, Ok(v.Integer(6)))
  let assert #(0, Error(Crashed(break.UndefinedReference(ir.Package("six"))))) =
    run.expression(ir.package("six"), [], 0, count, resolve)
}

pub fn a_block_returns_its_scope_after_an_effect_in_a_function_test() {
  let source =
    ir.let_(
      "f",
      ir.lambda("_", ask()),
      ir.let_("a", ir.integer(1), ir.apply(ir.variable("f"), ir.unit())),
    )
  let assert #(1, Ok(#(Some(v.Integer(1)), [#("a", _), #("f", _)]))) =
    run.block(source, [], 0, count, run.no_references)
}

pub fn a_block_ending_in_a_let_has_no_value_test() {
  let source = ir.let_("a", ask(), ir.vacant())
  assert run.block(source, [], 0, count, run.no_references)
    == #(1, Ok(#(None, [#("a", v.Integer(1))])))
}

pub fn an_async_handler_is_awaited_between_effects_test() {
  let handle = fn(total, label, lift) {
    promise.resolve(count(total, label, lift))
  }
  use result <- promise.map(run.expression_async(
    ir.add(ask(), ask()),
    [],
    0,
    handle,
    run.no_references,
  ))
  assert result == #(2, Ok(v.Integer(3)))
}

pub fn runtime_boundaries_do_not_dispatch_to_the_host_test() {
  let body = ir.lambda("_", ask())
  let assert #(0, Error(Crashed(break.MaskedEffect("Ask", _)))) =
    run.expression(
      ir.apply(ir.mask("Ask"), body),
      [],
      0,
      count,
      run.no_references,
    )
  let assert #(0, Error(Crashed(break.ImpureEffect("Ask", _)))) =
    run.expression(
      ir.call(ir.builtin("pure"), [body, ir.unit()]),
      [],
      0,
      count,
      run.no_references,
    )
}

pub fn async_blocks_keep_bindings_after_a_suspended_closure_test() {
  let source =
    ir.let_(
      "f",
      ir.lambda("_", ask()),
      ir.let_("n", ir.apply(ir.variable("f"), ir.unit()), ir.vacant()),
    )
  let handle = fn(total, label, lift) {
    promise.resolve(count(total, label, lift))
  }
  use result <- promise.map(run.block_async(
    source,
    [],
    0,
    handle,
    run.no_references,
  ))
  let assert #(1, Ok(#(None, scope))) = result
  let assert [#("n", v.Integer(1)), #("f", v.Closure(_, _, _))] = scope
}
