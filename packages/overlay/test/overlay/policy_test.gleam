import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/parser
import gleam/dict
import gleam/list
import overlay/policy
import touch_grass

fn rules(rule) {
  [#(touch_grass.now(), rule)]
}

fn gate() {
  v.Partial(v.Tag("Pass"), [])
}

pub fn required_field_present_is_gated_test() {
  let value = v.Record(dict.from_list([#("now", gate())]))
  let assert Ok(policy) =
    policy.decode_policy(rules(policy.PolicyField("now")), value)
  let assert Ok(policy.Interface(condition: policy.Gated(_), ..)) =
    dict.get(policy, "Now")
}

pub fn required_field_missing_is_an_error_test() {
  let assert Error(_) =
    policy.decode_policy(rules(policy.PolicyField("now")), v.unit())
}

pub fn unchecked_is_unrestricted_test() {
  let assert Ok(policy) =
    policy.decode_policy(rules(policy.Unchecked), v.unit())
  assert list.length(dict.keys(policy)) == 1
}

fn decide(code, input) {
  let assert Ok(source) = parser.all_from_string(code)
  let assert Ok(gate) = expression.execute(source, [])
  let assert Ok(policy) =
    policy.decode_policy(
      rules(policy.PolicyField("now")),
      v.Record(dict.from_list([#("now", gate)])),
    )
  policy.decide(
    policy,
    "Now",
    input,
    #(0, 0),
    fn(returned, then) { #(then(returned), "evaluated by host") },
    fn(action) { #(action, "no evaluation") },
  )
}

pub fn shared_decision_preserves_pass_and_mock_test() {
  let assert #(policy.Perform(interface, input), "evaluated by host") =
    decide("(_) -> { Pass({}) }", v.unit())
  assert interface.name == "Now"
  assert input == v.unit()
  let assert #(policy.Resume(value), "evaluated by host") =
    decide("(_) -> { Mock(42) }", v.unit())
  assert value == v.Integer(42)
}

pub fn shared_decision_preserves_gate_failures_test() {
  let assert #(
    policy.Failed(#(break.IncorrectTerm("Pass/Mock/Reject", _), _, _, _)),
    "evaluated by host",
  ) = decide("(_) -> { 42 }", v.unit())
  let assert #(
    policy.Failed(#(break.UnhandledEffect("NoGateEffects", _), _, _, _)),
    "evaluated by host",
  ) = decide("(_) -> { perform NoGateEffects({}) }", v.unit())
}

pub fn shared_decision_does_not_evaluate_unchecked_or_unavailable_test() {
  let assert Ok(policy) =
    policy.decode_policy(rules(policy.Unchecked), v.unit())
  let evaluate = fn(_, _) {
    panic as "unchecked effects must not evaluate gates"
  }
  let done = fn(action) { action }
  let assert policy.Perform(_, _) =
    policy.decide(policy, "Now", v.unit(), #(0, 0), evaluate, done)
  let assert policy.Unavailable =
    policy.decide(policy, "Post", v.unit(), #(0, 0), evaluate, done)
}

pub fn shared_decision_rejects_without_performing_or_mocking_test() {
  let assert #(policy.Unavailable, "evaluated by host") =
    decide("(_) -> { Reject({}) }", v.unit())
}
