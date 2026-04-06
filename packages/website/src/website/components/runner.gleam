import eyg/interpreter/break
import eyg/interpreter/state as istate
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import website/sync/cache

/// Return is parameterised because it can return the result of executing an expression or block
pub type Return(return, m) =
  Result(return, istate.Debug(m))

pub type Scope(m) =
  List(#(String, istate.Value(m)))

pub type Thunk(m) =
  fn() -> promise.Promise(istate.Value(m))

/// Handler is the lookup that returns a cast input
pub type Handler(ready, m) =
  fn(istate.Value(m)) -> Result(ready, istate.Reason(m))

pub type Effect(m) =
  #(String, #(istate.Value(m), istate.Value(m)))

pub type Runner(ready, return, m) {
  Runner(
    counter: Int,
    cache: cache.Cache,
    extrinsic: List(#(String, Handler(ready, m))),
    occured: List(Effect(m)),
    return: Return(return, m),
    awaiting: Option(Int),
    continue: Bool,
    resume: fn(istate.Value(m), istate.Env(m), istate.Stack(m)) ->
      Return(return, m),
  )
}

pub type Expression(ready, m) =
  Runner(ready, istate.Value(m), m)

pub type Block(ready, m) =
  Runner(ready, #(Option(istate.Value(m)), Scope(m)), m)

pub fn init(initial, cache, extrinsic, resume) -> Runner(_, r, m) {
  Runner(
    counter: 0,
    cache: cache,
    extrinsic: extrinsic,
    occured: [],
    return: initial,
    awaiting: None,
    continue: False,
    resume:,
  )
}

pub fn stop(state) {
  Runner(..state, continue: False)
}

pub type ExpressionMessage(m) =
  Message(istate.Value(m), m)

pub type BlockMessage(m) =
  Message(#(Option(istate.Value(m)), Scope(m)), m)

pub type Message(r, m) {
  Start
  HandlerCompleted(reference: Int, reply: istate.Value(m))
  Reset(return: Return(r, m))
  UpdateCache(cache.Cache)
}

pub type Action(return, ready) {
  Nothing
  RunExternalHandler(Int, ready)
  Conclude(return)
}

pub fn update(state, message) {
  case message {
    Start -> do(Runner(..state, continue: True))
    HandlerCompleted(ref, reply) -> handler_completed(state, ref, reply)
    Reset(return) -> reset(state, return)
    UpdateCache(cache) -> do(Runner(..state, cache:))
  }
}

fn reset(state, return) {
  let state =
    Runner(..state, return:, occured: [], awaiting: None, continue: False)
  #(state, Nothing)
}

fn handler_completed(state, ref, reply) {
  let Runner(occured:, return:, awaiting:, resume:, ..) = state
  case awaiting {
    Some(r) if r == ref ->
      case return {
        Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
          let occured = [#(label, #(lift, reply)), ..occured]
          let return = resume(reply, env, k)
          let state = Runner(..state, occured:, return:, awaiting: None)
          do(state)
        }
        _ -> panic as "should not be awaiting if not unhandled effect"
      }
    _ -> #(state, Nothing)
  }
}

fn do(state) {
  let Runner(awaiting:, ..) = state
  case awaiting {
    Some(_) -> #(state, Nothing)
    None -> {
      let Runner(counter:, cache:, extrinsic:, return:, continue:, resume:, ..) =
        state

      let return = cache.run(return, cache, resume)
      let state = Runner(..state, return:)
      case continue, return {
        True, Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
          case list.key_find(extrinsic, label) {
            Ok(handler) -> {
              case handler(lift) {
                Ok(thunk) -> {
                  let awaiting = Some(counter)
                  let action = RunExternalHandler(counter, thunk)
                  let counter = counter + 1
                  #(Runner(..state, counter:, awaiting:), action)
                }
                Error(reason) -> {
                  let return = Error(#(reason, meta, env, k))
                  #(Runner(..state, return:), Nothing)
                }
              }
            }
            _ -> {
              echo #("unknown effect", label)
              #(state, Nothing)
            }
          }
        }
        True, Ok(return) -> #(
          Runner(..state, continue: False),
          Conclude(return),
        )
        _, _ -> #(state, Nothing)
      }
    }
  }
}

pub fn run_thunk(ref, thunk) {
  promise.map(thunk(), HandlerCompleted(ref, _))
}
