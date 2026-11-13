import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/capture
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/interpreter/table
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import overlay/check
import overlay/policy
import touch_grass

fn gate(code) {
  let assert Ok(source) = parser.all_from_string(code)
  let assert Ok(value) = expression.execute(source, [])
  value
}

fn check_now(code) {
  check.value(gate(code), policy.gate_type(touch_grass.now()), #(0, 0), fn(_) {
    Error("unexpected reference")
  })
}

pub fn a_captured_continuation_is_rejected_before_type_checking_test() {
  let resume = v.Partial(v.Resume(#([], state.Env([], dict.new()))), [])
  let closure =
    v.Closure("_", #(ir.Variable("resume"), #(0, 0)), [#("resume", resume)])
  assert check.value(
      closure,
      policy.gate_type(touch_grass.now()),
      #(0, 0),
      fn(_) { Error("unexpected reference") },
    )
    == Error("A continuation cannot be type checked")
}

pub fn gate_input_and_reply_are_checked_before_execution_test() {
  assert check_now("(_) -> { Pass({}) }") == Ok(Nil)
  assert check_now("(_) -> { Mock(42) }") == Ok(Nil)
  assert check_now("(_) -> { Reject({}) }") == Ok(Nil)
  let assert Error(_) = check_now("(_) -> { Mock(\"not a time\") }")
  let assert Error(_) = check_now("(input) -> { Pass(!int_add(input, 1)) }")
  let assert Error(_) = check_now("(_) -> { Unknown({}) }")
}

pub fn effectful_gate_is_rejected_without_performing_its_effect_test() {
  let assert Error(_) =
    check_now("(input) -> { let _ = perform Leak(\"secret\") Pass(input) }")
}

pub fn captured_values_and_referenced_modules_are_checked_test() {
  let value = gate("let timestamp = 42\nlet f = (_) -> { Mock(timestamp) }\nf")
  assert check.value(value, policy.gate_type(touch_grass.now()), #(0, 0), fn(_) {
      Error("no references")
    })
    == Ok(Nil)
  let value = gate("(_) -> { Mock(import \"./time.eyg\") }")
  let lookup = fn(reference) {
    case reference {
      ir.Relative("./time.eyg") -> Ok(v.Integer(42))
      _ -> Error("unknown reference")
    }
  }
  assert check.value(
      value,
      policy.gate_type(touch_grass.now()),
      #(0, 0),
      lookup,
    )
    == Ok(Nil)
  let assert Error(_) =
    check.value(value, policy.gate_type(touch_grass.now()), #(0, 0), fn(_) {
      Ok(v.String("not a time"))
    })
}

pub fn complete_reject_all_has_the_required_policy_type_test() {
  let rules = [
    #(touch_grass.now(), policy.PolicyField("now")),
    #(
      touch_grass.map(touch_grass.fetch(), fn(_) { Nil }),
      policy.PolicyField("fetch"),
    ),
  ]
  let reject_all = policy.reject_all(rules, #(0, 0))
  assert check.value(reject_all, policy.type_(rules), #(0, 0), fn(_) {
      Error("no references")
    })
    == Ok(Nil)
  let assert Error(_) =
    check.value(v.unit(), policy.type_(rules), #(0, 0), fn(_) {
      Error("no references")
    })
}

pub fn nested_interface_variables_are_registered_without_colliding_test() {
  let expected =
    t.Fun(t.Fun(t.Var(17), t.Var(23), t.Var(42)), t.Empty, t.String)
  let lookup = fn(_) { Error("no references") }
  assert check.value(gate("(_) -> { \"allowed\" }"), expected, #(0, 0), lookup)
    == Ok(Nil)
  let assert Error(_) =
    check.value(gate("(_) -> { 42 }"), expected, #(0, 0), lookup)
}

pub fn tables_cannot_hide_captured_continuations_test() {
  let resume = v.Partial(v.Resume(#([], state.Env([], dict.new()))), [])
  assert !capture.is_capturable(v.Table(table.singleton("Row", resume), []))
  assert !capture.is_capturable(v.Table(dict.new(), [resume]))
  assert capture.is_capturable(gate("fact Row({value: 42})"))
}
