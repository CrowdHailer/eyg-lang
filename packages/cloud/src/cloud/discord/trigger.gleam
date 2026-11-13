//// Discord automations, checked and evaluated once at startup.

import cloud/beam/execute
import cloud/beam/file_system
import cloud/discord/event as discord
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import touch_grass/interface

pub opaque type Checked {
  Checked(name: String, function: state.Value(execute.Meta))
}

pub fn prepare(
  triggers: List(#(String, String)),
  state: execute.State,
  policy: execute.Policy,
) -> Result(#(List(Checked), execute.State), String) {
  use #(checked, state) <- result.map(
    list.try_fold(triggers, #([], state), fn(acc, trigger) {
      let #(checked, state) = acc
      let #(name, code) = trigger
      use #(function, state) <- result.map(
        prepare_discord(code, state, policy)
        |> result.map_error(fn(reason) { "Trigger " <> name <> ": " <> reason }),
      )
      #([Checked(name, function), ..checked], state)
    }),
  )
  #(list.reverse(checked), state)
}

fn prepare_discord(code, state, policy: execute.Policy) {
  use source <- result.try(
    parser.all_from_string(code)
    |> result.map_error(parser.format_error(_, code)),
  )
  let effects =
    dict.values(policy)
    |> list.map(fn(entry) { entry.interface })
    |> interface.types
  let base =
    infer.pure()
    |> infer.with_effects(effects)
    |> infer.with_expected_type(t.unit)
  let context = infer.Context(..base, env: [#("$event", discord.type_())])
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

pub fn run(
  trigger: Checked,
  channel_name: String,
  event: discord.Event,
  state,
  policy,
  files,
  emit,
) {
  let #(outcome, state, files) =
    execute.call(
      trigger.function,
      discord.to_eyg(channel_name, event),
      state,
      policy,
      files,
      emit,
    )
  #(
    result.map_error(outcome, fn(reason) {
      "Trigger " <> trigger.name <> ": " <> reason
    }),
    state,
    files,
  )
}

/// Execute at the Discord polling hook. File state lasts for this event; the
/// reference cache and configured workspace secrets are retained by the client.
pub fn run_all(triggers, channel_name, event, state, policy, emit) {
  let #(state, _) =
    list.fold(triggers, #(state, file_system.new(dict.new())), fn(acc, trigger) {
      let #(state, files) = acc
      let #(outcome, state, files) =
        run(trigger, channel_name, event, state, policy, files, emit)
      case outcome {
        Ok(Nil) -> Nil
        Error(reason) -> emit(execute.StandardError(reason))
      }
      #(state, files)
    })
  state
}
