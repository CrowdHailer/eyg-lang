//// Policies decide every effect an agent's program performs.
////
//// A policy is a record of gate functions, one field per effect, named in snake case.
//// `ReadFile` is decided by the `read_file` field and a host effect `Task` by `task`.
//// An effect without a field is unavailable.
////
//// A subagent's policy is restricted by its parent's.
//// Each effect is decided by the child's gate first and the result passed to the parent's gate,
//// an effect is only available if every policy in the chain has a field for it.

import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict.{type Dict}
import gleam/list
import gleam/string
import loam/execute

/// Gates for each policy field, the most restrictive gate first.
pub opaque type Policy {
  Policy(gates: Dict(String, List(execute.Value)))
}

/// Effects that need no decision, they compute a value without reaching outside the program.
pub const unchecked = ["DecodeJSON", "EYGParse", "Flip", "Hash", "Random"]

/// Effects that only add to the tool result, they are allowed unless the policy has a gate for them.
pub const captured = ["StandardOut", "StandardError"]

pub fn from_value(value: execute.Value) -> Result(Policy, String) {
  case cast.as_record(value) {
    Ok(fields) ->
      fields
      |> dict.map_values(fn(_, gate) { [gate] })
      |> Policy
      |> Ok
    Error(_) -> Error("a policy must be a record of gate functions")
  }
}

/// The child policy can only remove or further restrict what the parent allows.
pub fn restrict(
  parent: Policy,
  child: execute.Value,
) -> Result(Policy, String) {
  case cast.as_record(child) {
    Ok(fields) -> {
      // An empty chain is an explicit denial. Keep it through descendants so
      // omitted gates cannot reopen effects that are available by default.
      let inherited =
        dict.map_values(parent.gates, fn(name, gates) {
          case gates, dict.get(fields, name) {
            [_, ..], Ok(gate) -> [gate, ..gates]
            _, _ -> []
          }
        })
      let defaults = list.append(unchecked, captured) |> list.map(field)
      let gates =
        list.fold(dict.to_list(fields), inherited, fn(gates, entry) {
          let #(name, gate) = entry
          case
            !dict.has_key(parent.gates, name) && list.contains(defaults, name)
          {
            True -> dict.insert(gates, name, [gate])
            False -> gates
          }
        })
      Ok(Policy(gates))
    }
    Error(_) -> Error("a policy must be a record of gate functions")
  }
}

pub type Access {
  /// Gates to run, in order, before performing the effect.
  Gated(List(execute.Value))
  Open
  Unavailable
}

pub fn access(policy: Policy, label: String) -> Access {
  case dict.get(policy.gates, field(label)) {
    Ok([]) -> Unavailable
    Ok(gates) -> Gated(gates)
    Error(Nil) ->
      case list.contains(unchecked, label) || list.contains(captured, label) {
        True -> Open
        False -> Unavailable
      }
  }
}

pub fn fields(policy: Policy) -> List(String) {
  policy.gates
  |> dict.to_list
  |> list.filter_map(fn(entry) {
    case entry.1 {
      [] -> Error(Nil)
      _ -> Ok(entry.0)
    }
  })
  |> list.sort(string.compare)
}

/// The policy field for an effect label, `ReadFile` is decided by `read_file`, `CWD` by `cwd`.
pub fn field(label: String) -> String {
  label
  |> string.to_graphemes
  |> do_field(False, [])
}

fn do_field(letters, previous_lower, acc) {
  case letters {
    [] -> acc |> list.reverse |> string.concat
    [letter, ..rest] -> {
      let lower = string.lowercase(letter)
      let is_upper = lower != letter
      let acc = case is_upper && previous_lower {
        True -> [lower, "_", ..acc]
        False -> [lower, ..acc]
      }
      do_field(rest, !is_upper, acc)
    }
  }
}

/// Gates may return a decision to perform the effect with a (possibly changed) value or a value to resume with.
pub type Decision {
  Pass(execute.Value)
  Mock(execute.Value)
}

pub fn decision(value: execute.Value) -> Result(Decision, Nil) {
  case value {
    v.Tagged("Pass", inner) -> Ok(Pass(inner))
    v.Tagged("Mock", inner) -> Ok(Mock(inner))
    _ -> Error(Nil)
  }
}
