import eyg/ir/tree as ir
import eyg/runtime/break
import eyg/runtime/interpreter/block
import eyg/runtime/interpreter/state as istate
import eyg/runtime/value as v
import eyg/sync/sync
import gleam/dict
import gleam/dynamic
import gleam/dynamicx
import gleam/javascript/promise
import gleam/list
import gleam/option
import harness/stdlib
import morph/editable

pub type Run {
  Run(status: Status, effects: List(#(String, #(Value, Value))))
}

pub type Meta =
  Nil

pub type Value =
  v.Value(Meta, #(List(#(istate.Kontinue(Meta), Meta)), istate.Env(Meta)))

pub type Reason =
  break.Reason(Meta, #(List(#(istate.Kontinue(Meta), Meta)), istate.Env(Meta)))

pub type Status {
  Done(option.Option(Value), List(#(String, Value)))
  Handling(
    label: String,
    lift: Value,
    env: istate.Env(Meta),
    k: istate.Stack(Meta),
    blocking: fn(Value) -> Result(promise.Promise(Value), Reason),
  )
  Failed(istate.Debug(Meta))
}

// effects are not a map of functions we don't use that for stateful running
pub fn start(editable, scope, effects, cache) {
  let return =
    block.execute(
      editable.to_annotated(editable, []) |> ir.clear_annotation,
      stdlib.new_env(
        scope,
        sync.named_values(cache)
          |> dict.from_list
          // TODO move all unsafe into stdlib
          |> dynamic.from()
          |> dynamicx.unsafe_coerce(),
      ),
      // effects
      dict.new(),
    )
  let status = case return {
    Ok(#(value, env)) -> Done(value, env)
    Error(debug) -> handle_extrinsic_effects(debug, effects)
  }
  Run(status, [])
}

pub fn handle_extrinsic_effects(debug, effects) {
  let #(reason, _meta, env, k) = debug
  case reason {
    break.UnhandledEffect(label, lift) ->
      case list.key_find(effects, label) {
        Ok(#(_lift, _reply, blocking)) ->
          Handling(label, lift, env, k, blocking)
        _ -> Failed(debug)
      }
    _ -> Failed(debug)
  }
}
