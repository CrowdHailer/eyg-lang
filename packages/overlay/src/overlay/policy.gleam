//// Bind a host's effect rules to a runtime policy.

import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import touch_grass/interface

/// Require a user-supplied gate in the named field or
/// expose the effect without a user-supplied gate.
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

/// Host rules select which effects are available, effects without a host rule are unavailable.
pub fn match_rules(
  harness: interface.Harness(a, meta),
  rules: List(#(String, Rule)),
) {
  list.filter_map(harness, fn(interface) {
    let interface.Interface(name:, ..) = interface
    case list.key_find(rules, name) {
      Ok(rule) -> Ok(#(interface, rule))
      Error(Nil) -> Error(Nil)
    }
  })
}

pub fn decode_policy(
  rules: List(#(interface.Interface(_, _), Rule)),
  value: state.Value(_),
) {
  use fields <- result.map(
    list.try_map(rules, fn(rule) {
      let #(interface, rule) = rule
      let name = interface.name
      case rule {
        PolicyField(field) ->
          case cast.field(field, Ok, value) {
            Ok(gate) -> Ok(#(name, Interface(interface, Gated(gate))))
            Error(reason) -> Error(reason)
          }
        Unchecked -> Ok(#(name, Interface(interface, Unrestricted)))
      }
    }),
  )
  dict.from_list(fields)
}

/// The decision of running a policy function.
pub type Decision(meta) {
  Pass(state.Value(meta))
  Mock(state.Value(meta))
}

/// Decode the runtime decision value into Gleam value.
pub fn decision_from_value(
  value: state.Value(meta),
) -> Result(Decision(meta), Nil) {
  case value {
    v.Tagged("Pass", inner) -> Ok(Pass(inner))
    v.Tagged("Mock", inner) -> Ok(Mock(inner))
    _ -> Error(Nil)
  }
}
