import eyg/runtime/break
import eyg/runtime/interpreter/runner
import eyg/runtime/interpreter/state as istate
import eyg/runtime/value as v
import eyg/sync/sync
import eygir/annotated
import gleam/dict
import gleam/dynamic
import gleam/dynamicx
import gleam/javascript/promise
import gleam/list
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
  Done(Value)
  Handling(
    label: String,
    lift: Value,
    env: istate.Env(Meta),
    k: istate.Stack(Meta),
    blocking: fn(Value) -> Result(promise.Promise(Value), Reason),
  )
  Failed(istate.Debug(Meta))
}

pub fn start(editable, effects, cache) {
  let return =
    runner.execute(
      editable.to_expression(editable)
        |> annotated.add_annotation(Nil),
      stdlib.env_and_ref(
        sync.values(cache)
        // TODO move all unsafe into stdlib
        |> dynamic.from()
        |> dynamicx.unsafe_coerce(),
      ),
      // effects
      dict.new(),
    )
  let status = case return {
    Ok(value) -> Done(value)
    Error(debug) -> handle_extrinsic_effects(debug, effects)
  }
  Run(status, [])
}

// pub fn do(label, lift, env, k, blocking) {
//   case blocking(lift) {
//     Error(reason) -> Failed(#(reason, Nil, env, k))
//     Ok(promise) -> promise.map(promise, fn(value){
//    todo   
//     })
//   }
// }

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
