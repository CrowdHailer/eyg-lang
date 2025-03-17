import eyg/interpreter/block
import eyg/interpreter/state as istate
import eyg/ir/tree as ir
import gleam/javascript/promise
import gleam/listx
import gleam/option.{type Option, Some}

import morph/analysis
import morph/editable as e

import website/sync/cache

// The interactive mount always evaluates new code
// it is used in the example -> rename from snippet

pub type Scope =
  List(#(String, analysis.Value))

pub type Return =
  Result(#(Option(analysis.Value), Scope), istate.Debug(analysis.Path))

pub type RuntimeEffect {
  RuntimeEffect(label: String, lift: analysis.Value, reply: analysis.Value)
}

pub type Run {
  NotRunning
  // if no type errors then unhandled effect is still running
  Running(Return, List(RuntimeEffect))
}

pub type Interactive {
  Interactive(
    // Might be nice to remove this
    editable: e.Expression,
    // ------------------
    // Context of code snippet
    // scope before anything runs
    // TODO remove this from expression
    scope: Scope,
    // spec of effects available at the top level
    effects: List(#(String, analysis.EffectSpec)),
    cache: cache.Cache,
    // ------------------
    // Analysis might need to change i.e. reload
    analysis: Option(analysis.Analysis),
    // ------------------
    // Run object could be global would change in other components
    // Computed values, relies on the cache, scope and effects
    // this is the value from the expression not part of run at all
    evaluated: Return,
    // A snippet can have multiple runs, the task counter needs to be unique over all of them
    // Could be task id and we have one central task runner
    task_counter: Int,
    run: Run,
  )
}

pub fn init(editable, scope, effects, cache) {
  Interactive(
    editable: editable,
    scope: scope,
    effects: effects,
    cache: cache,
    analysis: Some(do_analysis(editable, scope, cache, effect_types(effects))),
    // analysis: None,
    evaluated: evaluate(editable, scope, cache),
    task_counter: -1,
    run: NotRunning,
  )
}

pub fn do_analysis(editable, scope, cache, effects) {
  let refs = cache.type_map(cache)

  let analysis =
    analysis.do_analyse(
      editable,
      analysis.within_environment(scope, refs, Nil)
        |> analysis.with_effects(effects),
    )
  analysis
}

pub fn effect_types(effects: List(#(String, analysis.EffectSpec))) {
  listx.value_map(effects, fn(details) { #(details.0, details.1) })
}

pub fn source(state) {
  let Interactive(editable:, ..) = state
  editable
}

pub fn set_references(state: Interactive, cache) {
  // If evaluated changes then run should change in the same way
  let evaluated = evaluate(source(state), state.scope, cache)
  let run = case state.run {
    NotRunning -> state.run
    Running(return, effects) ->
      Running(cache.run(return, cache, block.resume), effects)
  }
  let analysis =
    Some(do_analysis(
      state.editable,
      state.scope,
      cache,
      effect_types(state.effects),
    ))
  Interactive(..state, cache:, evaluated:, run:, analysis:)
}

pub fn evaluate(editable, scope, cache) {
  e.to_annotated(editable, [])
  |> ir.clear_annotation
  |> block.execute(scope)
  |> cache.run(cache, block.resume)
}

pub type Effect {
  Nothing
  RunEffect(promise.Promise(#(Int, analysis.Value)))
  Conclude(
    value: Option(analysis.Value),
    effects: List(RuntimeEffect),
    scope: Scope,
  )
}
