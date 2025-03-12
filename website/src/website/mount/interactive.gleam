import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/state as istate
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dict
import gleam/dynamicx
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}

import morph/analysis
import morph/editable as e

import website/sync/cache

// The interactive mount always evaluates new code
// it is used in the example -> rename from snippet

type Scope =
  List(#(String, analysis.Value))

type Return =
  Result(#(Option(analysis.Value), Scope), istate.Debug(analysis.Path))

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
    analysis: Some(do_analysis(editable, scope, cache, effects)),
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
      analysis.within_environment(scope, refs, Nil),
      effects,
    )
  analysis
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
    Some(do_analysis(state.editable, state.scope, cache, state.effects))
  Interactive(..state, cache:, evaluated:, run:, analysis:)
}

fn evaluate(editable, scope, cache) {
  e.to_annotated(editable, [])
  |> ir.clear_annotation
  |> block.execute(scope)
  |> cache.run(cache, block.resume)
}

pub type RuntimeEffect {
  RuntimeEffect(label: String, lift: analysis.Value, reply: analysis.Value)
}

fn run_handle_effect(state, task_id, value) {
  let Interactive(task_counter: id, run: run, ..) = state
  case run, id == task_id {
    Running(
      Error(#(break.UnhandledEffect(label, lift), _meta, env, k)),
      effects,
    ),
      True
    -> {
      let effects = [RuntimeEffect(label, lift, value), ..effects]
      let task_id = task_id + 1
      let #(return, task) =
        block.resume(value, env, k)
        |> run_blocking(state.cache, state.effects, block.resume)
      let run = Running(return, effects)
      let state = Interactive(..state, task_counter: task_id, run: run)
      let ef = case return {
        Ok(#(value, scope)) -> Conclude(value, effects, scope)
        _ ->
          case task {
            Some(task) -> {
              let p = promise.map(task, fn(v) { #(task_id, v) })
              RunEffect(p)
            }
            None -> Nothing
          }
      }
      #(state, ef)
    }
    _, _ -> #(state, Nothing)
  }
  // case status {
  //   run.Failed(_) -> #(state, Nothing)
  //   run.Done(value, env) -> #(state, Conclude(value, run.effects, env))

  //   run.Handling(_label, lift, env, k, blocking) ->
  //     case blocking(lift) {
  //       Ok(promise) -> {
  //         let run = run.Run(status, effect_log)
  //         let state = Snippet(..state, run: run)
  //         #(state, RunEffect(promise))
  //       }
  //       Error(reason) -> {
  //         let run = run.Run(run.Failed(#(reason, Nil, env, k)), effect_log)
  //         let state = Snippet(..state, run: run)
  //         #(state, Nothing)
  //       }
  //     }
  // }
}

// might belong on a run 
fn run_blocking(return, cache, extrinsic, resume) {
  let return = cache.run(return, cache, resume)
  case return {
    Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      case list.key_find(extrinsic, label) {
        Ok(#(_lift, _reply, blocking)) ->
          case blocking(lift) {
            Ok(p) -> #(return, Some(p))
            Error(reason) -> #(Error(#(reason, meta, env, k)), None)
          }
        _ -> #(return, None)
      }
    }
    _ -> #(return, None)
  }
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

fn run_effects(state) {
  let Interactive(evaluated: evaluated, task_counter: task_counter, ..) = state
  let task_counter = task_counter + 1
  let #(return, task) =
    run_blocking(evaluated, state.cache, state.effects, block.resume)
  let run = Running(return, [])
  let state = Interactive(..state, run: run, task_counter: task_counter)
  case task {
    Some(p) -> {
      let p = promise.map(p, fn(v) { #(task_counter, v) })
      #(state, RunEffect(p))
    }
    None -> #(state, Nothing)
  }
}
