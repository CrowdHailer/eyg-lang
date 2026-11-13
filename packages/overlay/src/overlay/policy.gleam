//// Bind a host's effect rules to a runtime policy.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import touch_grass/interface

/// Require a gate in the named field or expose a deterministic effect without one.
pub type Rule {
  PolicyField(String)
  Unchecked
}

pub type Condition(meta) {
  Gated(state.Value(meta))
  Unrestricted
}

pub type Interface(a, meta) {
  Interface(interface: interface.Interface(a, meta), condition: Condition(meta))
}

pub type Policy(a, meta) =
  Dict(String, Interface(a, meta))

/// Filter a harness, the full set of interfaces on a platform, down to the supported set and the associated rule.
/// The rule links an interface to a field on a provided policy object.
/// Any interface in the harness not mentioned by a rule is filtered out and will not appear in type inference it can never be called.
pub fn match_rules(
  harness: interface.Harness(eff, meta),
  rules: List(#(String, Rule)),
) -> List(#(interface.Interface(eff, meta), Rule)) {
  list.filter_map(harness, fn(interface) {
    let interface.Interface(name:, ..) = interface
    case list.key_find(rules, name) {
      Ok(rule) -> Ok(#(interface, rule))
      Error(Nil) -> Error(Nil)
    }
  })
}

pub fn type_(rules: List(#(interface.Interface(_, _), Rule))) {
  let fields =
    list.filter_map(rules, fn(rule) {
      let #(interface, rule) = rule
      case rule {
        PolicyField(field) -> Ok(#(field, gate_type(interface)))
        Unchecked -> Error(Nil)
      }
    })
  t.record(fields)
}

pub fn gate_type(interface: interface.Interface(_, _)) {
  t.Fun(
    interface.lift_type,
    t.Empty,
    t.union([
      #("Pass", interface.lift_type),
      #("Mock", interface.lower_type),
      #("Reject", t.unit),
    ]),
  )
}

/// A complete, pure policy that refuses every gated effect. Hosts can expose
/// this value so configuration overwrites individual gates without omitting any.
pub fn reject_all(
  rules: List(#(interface.Interface(_, meta), Rule)),
  meta: meta,
) {
  let body = ir.tagged("Reject", ir.unit()) |> ir.map_annotation(fn(_) { meta })
  let reject = v.Closure("_", body, [])
  rules
  |> list.filter_map(fn(rule) {
    case rule.1 {
      PolicyField(field) -> Ok(#(field, reject))
      Unchecked -> Error(Nil)
    }
  })
  |> dict.from_list
  |> v.Record
}

pub fn decode_policy(
  rules: List(#(interface.Interface(_, _), Rule)),
  value: state.Value(_),
) {
  use fields <- result.map(
    list.try_fold(rules, [], fn(fields, rule) {
      let #(interface, rule) = rule
      let name = interface.name
      case rule {
        PolicyField(field) ->
          case cast.field(field, Ok, value) {
            Ok(gate) ->
              Ok([#(name, Interface(interface, Gated(gate))), ..fields])
            Error(reason) -> Error(reason)
          }
        Unchecked -> Ok([#(name, Interface(interface, Unrestricted)), ..fields])
      }
    }),
  )
  dict.from_list(fields)
}

/// The decision of running a policy function.
pub type Decision(meta) {
  Pass(state.Value(meta))
  Mock(state.Value(meta))
  Reject
}

/// What to do after a decision
pub type Action(m, eff) {
  Perform(interface: interface.Interface(eff, m), input: state.Value(m))
  Resume(state.Value(m))
  Failed(state.Debug(m))
  Unavailable
}

/// Decide an effect using the host's pure evaluator. The evaluator owns reference
/// resolution and its state or asynchronous effects; this module only interprets
/// the gate's result. `done` lifts decisions that need no evaluation into the same
/// host result type.
pub fn decide(
  policy: Policy(eff, meta),
  label: String,
  input: state.Value(meta),
  meta: meta,
  evaluate: fn(
    Result(state.Value(meta), state.Debug(meta)),
    fn(Result(state.Value(meta), state.Debug(meta))) -> Action(meta, eff),
  ) -> output,
  done: fn(Action(meta, eff)) -> output,
) -> output {
  case dict.get(policy, label) {
    Ok(Interface(interface, Gated(gate))) -> {
      use returned <- evaluate(expression.call(gate, [#(input, meta)]))
      case returned {
        Ok(value) ->
          case decision_from_value(value) {
            Ok(Pass(modified)) -> Perform(interface, modified)
            Ok(Mock(value)) -> Resume(value)
            Ok(Reject) -> Unavailable
            Error(Nil) ->
              Failed(#(
                break.IncorrectTerm(expected: "Pass/Mock/Reject", got: value),
                meta,
                builtin.default([]),
                state.Empty,
              ))
          }
        Error(debug) -> Failed(debug)
      }
    }
    Ok(Interface(interface, Unrestricted)) -> done(Perform(interface, input))
    Error(Nil) -> done(Unavailable)
  }
}

/// Decode the runtime decision value into Gleam value.
pub fn decision_from_value(
  value: state.Value(meta),
) -> Result(Decision(meta), Nil) {
  case value {
    v.Tagged("Pass", inner) -> Ok(Pass(inner))
    v.Tagged("Mock", inner) -> Ok(Mock(inner))
    v.Tagged("Reject", inner) ->
      cast.as_unit(inner, Reject) |> result.replace_error(Nil)
    _ -> Error(Nil)
  }
}
