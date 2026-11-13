//// Automations checked against a platform's event type at startup.

import cloud/beam/execute
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/tree as ir
import eyg/parser
import gleam/list
import gleam/result
import gleam/string
import overlay/policy
import touch_grass/harness/computer
import touch_grass/interface

pub type Checked =
  state.Value(execute.Meta)

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
  use source <- result.try(
    parser.all_from_string(code)
    |> result.map_error(parser.format_error(_, code)),
  )
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
      let #(value, cache) = execute.lookup(reference, state)
      let type_ = {
        use _ <- result.try(result.replace_error(value, Nil))
        use module <- result.map(cache.get_reference(cache, reference))
        module.type_
      }
      check(resume(type_), execute.State(..state, cache:))
    }
  }
}
