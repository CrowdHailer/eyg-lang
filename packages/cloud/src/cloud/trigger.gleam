//// Automations checked against a platform's event type at startup.

import cloud/beam/execute
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/list
import gleam/result
import gleam/string
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/policy
import touch_grass/source

pub type Checked =
  state.Value(source.Location)

pub fn prepare(
  triggers: List(#(String, String)),
  event_type: t.Type(#(Bool, Int)),
  state: execute.State,
) -> Result(#(List(Checked), execute.State), String) {
  prepare_returning(triggers, event_type, t.unit, state)
}

/// Check triggers that produce a value for their caller.
pub fn prepare_returning(
  triggers: List(#(String, String)),
  event_type: t.Type(#(Bool, Int)),
  return_type: t.Type(Int),
  state: execute.State,
) -> Result(#(List(Checked), execute.State), String) {
  use #(checked, state) <- result.map(
    list.try_fold(triggers, #([], state), fn(acc, trigger) {
      let #(checked, state) = acc
      let #(name, code) = trigger
      use #(function, state) <- result.map(
        prepare_function(code, event_type, return_type, state)
        |> result.map_error(fn(reason) { "Trigger " <> name <> ": " <> reason }),
      )
      #([function, ..checked], state)
    }),
  )
  #(list.reverse(checked), state)
}

fn prepare_function(code, event_type, return_type, state) {
  use source <- result.try(source.parse(code, source.Inline))
  let effects =
    policy.match_rules(computer.effects(), execute.rules)
    |> list.map(fn(rule) { rule.0 })
    |> interface.types
  let base =
    infer.pure()
    |> infer.with_effects(effects)
    |> infer.with_expected_type(return_type)
  let context = infer.Context(..base, env: [#("$event", event_type)])
  // Check the call so a trigger can use any subset of the available effects.
  let call = #(ir.Apply(source, #(ir.Variable("$event"), source.1)), source.1)
  let #(analysis, state) = check(infer.check(context, call), state)
  case infer.all_errors(analysis) {
    [] -> {
      let #(value, state) =
        execute.pure_loop(expression.execute(source, []), state)
      use value <- result.map(
        result.map_error(value, fn(debug) { simple_debug.describe(debug.0) }),
      )
      #(value, state)
    }
    errors ->
      Error(
        errors
        |> list.map(fn(error) { debug.render_reason(error.1) })
        |> string.join("\n"),
      )
  }
}

fn check(step, state: execute.State) {
  case step {
    infer.Done(analysis) -> #(analysis, state)
    infer.Lookup(reference, resume) -> {
      let #(type_, state) = execute.lookup_type(reference, state)
      let type_ = result.replace_error(type_, Nil)
      check(resume(type_), state)
    }
  }
}
