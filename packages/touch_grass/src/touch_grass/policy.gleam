//// Bind a host's effect rules to a runtime policy.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/cast
import eyg/interpreter/evaluation
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import touch_grass/file_system
import touch_grass/interface
import touch_grass/source

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
        PolicyField(field) ->
          Ok(#(
            field,
            t.Fun(
              interface.lift_type,
              t.Empty,
              t.union([
                #("Pass", interface.lift_type),
                #("Mock", interface.lower_type),
              ]),
            ),
          ))
        Unchecked -> Error(Nil)
      }
    })
  t.record(fields)
}

/// Check that policy construction and its gates are pure and match the rules.
/// The host supplies dependency types through the inference lookup requests.
pub fn check(
  source: ir.Node(meta),
  rules: List(#(interface.Interface(eff, meta), Rule)),
) -> infer.Step(infer.Analysis(meta)) {
  infer.pure()
  |> infer.with_expected_type(type_(rules))
  |> infer.check(source)
}

// TODO accept checked source so preparation can reuse its resolved dependencies.
pub fn prepare(
  code: String,
  input: source.Origin,
  rules: List(#(interface.Interface(t, source.Location), Rule)),
) -> evaluation.Evaluation(
  Result(Policy(t, source.Location), String),
  state.Value(source.Location),
  source.Location,
) {
  case source.parse(code, input) {
    Ok(source) -> prepare_source(source, rules)
    Error(reason) -> evaluation.Done(Error(reason))
  }
}

pub fn prepare_source(
  source: #(ir.Expression(meta), meta),
  rules: List(#(interface.Interface(a, meta), Rule)),
) -> evaluation.Evaluation(
  Result(Dict(String, Interface(a, meta)), String),
  v.Value(meta, #(List(#(state.Kontinue(meta), meta)), state.Env(meta))),
  meta,
) {
  let outcome = evaluation.await(expression.execute(source, []))
  use returned <- evaluation.map(outcome)
  case returned {
    Ok(value) ->
      case decode_policy(rules, value) {
        Ok(policy) -> Ok(policy)
        Error(reason) -> Error(simple_debug.describe(reason))
      }
    Error(#(reason, _, _, _)) -> Error(simple_debug.describe(reason))
  }
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

/// What to do after a decision
pub type Action(m, eff) {
  Perform(interface: interface.Interface(eff, m), input: state.Value(m))
  Resume(state.Value(m))
  Failed(state.Debug(m))
  Unavailable
}

/// Decide an effect using the host's pure evaluator. The host owns reference
/// resolution and state; `done` handles decisions that need no evaluation.
/// TODO remove this one
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
      action_from_outcome(returned, interface, meta)
    }
    Ok(Interface(interface, Unrestricted)) -> done(Perform(interface, input))
    Error(Nil) -> done(Unavailable)
  }
}

pub fn decide_host(
  policy: Policy(eff, source.Location),
  label: String,
  input: state.Value(source.Location),
  meta: source.Location,
  cwd: String,
) -> evaluation.Evaluation(
  Action(source.Location, eff),
  state.Value(source.Location),
  source.Location,
) {
  let base = source.base(meta.origin, cwd)
  case file_system.resolve_input(base, label, input) {
    Ok(input) -> decide_m(policy, label, input, meta)
    Error(_) -> evaluation.Done(Resume(v.error(v.String("invalid path"))))
  }
}

pub fn decide_m(
  policy: Policy(eff, meta),
  label: String,
  input: state.Value(meta),
  meta: meta,
) -> evaluation.Evaluation(Action(meta, eff), state.Value(meta), meta) {
  case dict.get(policy, label) {
    Ok(Interface(interface, Gated(gate))) -> {
      use returned <- evaluation.map(
        evaluation.await(expression.call(gate, [#(input, meta)])),
      )
      action_from_outcome(returned, interface, meta)
    }
    Ok(Interface(interface, Unrestricted)) ->
      evaluation.Done(Perform(interface, input))

    Error(Nil) -> evaluation.Done(Unavailable)
  }
}

fn action_from_outcome(returned, interface, meta) {
  case returned {
    Ok(value) ->
      case decision_from_value(value) {
        Ok(Pass(modified)) -> Perform(interface, modified)
        Ok(Mock(value)) -> Resume(value)
        Error(Nil) ->
          Failed(#(
            break.IncorrectTerm(expected: "Pass/Mock", got: value),
            meta,
            builtin.default([]),
            state.Empty,
          ))
      }
    Error(debug) -> Failed(debug)
  }
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
