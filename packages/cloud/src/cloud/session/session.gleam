//// This session module
//// Always assumes a box exists
//// Does not at this time implement any agent support

import cloud/beam/execute
import envoy
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/state as istate
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/location
import gleam/dict
import gleam/http/response
import gleam/json
import gleam/result
import multiformats/cid/v1
import ogre/origin
import simplifile
import touch_grass/harness/computer
import touch_grass/interface
import unixfs
import unixfs/mfs

pub type Event {
  Event(
    session: String,
    sequence: Int,
    recorded_at: String,
    payload: EventPayload,
  )
}

pub type BoxSequence =
  Int

pub type EventPayload {
  Trigger(trigger: Trigger, at: BoxSequence)
  Executed(
    break: String,
    sync_events: List(#(String, istate.Value(Nil))),
    commit: Result(BoxSequence, String),
  )
}

pub type Trigger {
  UserSubmittedCode(code: String)
  FetchCompleted(response.Response(BitArray))
}

pub fn begin(box_id, code, blobs) {
  use #(box_sequence, root) <- result.try(load_box(box_id))
  // validate that the source can be parsed first
  let trigger = UserSubmittedCode(code)
  use event <- result.try(start_session(trigger, box_sequence))
  // The event has been saved
  let assert Trigger(trigger: UserSubmittedCode(code:), at: _) = event.payload
  let secrets = dict.new()

  let policy = dict.new()
  let assert Ok(policy_code) = simplifile.read("policy.eyg")
  let assert Ok(hub) =
    envoy.get("EYG_ORIGIN")
    |> result.unwrap("https://eyg.run")
    |> origin.from_string_strict

  let #(policy, execute_state) =
    execute.load_policy(
      policy_code,
      execute.State(origin: hub, cache: cache.ready(), secrets:, blobs: blobs),
    )
  let assert Ok(policy) = policy
  // echo execute_state
  // assert at == root
  case parse(code) {
    Ok(source) -> {
      // TODO the scope will stay
      loop(block.execute(source, []))

      echo source
      todo
    }
    Error(_) -> todo
  }
  // let #(result, state, root, logs) =
  //   execute.block(
  //     code,
  //     execute.State(
  //       origin: origin.https("eyg.run"),
  //       cache: cache.ready(),
  //       secrets:,
  //       blobs:,
  //     ),
  //     policy,
  //     root,
  //     fn(_) { Nil },
  //   )
  // state is execute state and stays in process
  // result might be a lift/value/error
  // root is the new file system root before merging
  // logs needs extending to all the sync events that happened i.e. random

  // READ latest file system
  // 3 way merge and write the Executed event and new Box state in one transaction

  // If there is a break for an effect then start running the effect
  // echo result
  echo root
  Ok(todo)
}

fn loop(return) {
  case return {
    Ok(value) -> todo
    Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      case interface.cast(computer.effects(), label, lift) {
        Ok(effect) -> perform_effect()
        Error(_) -> todo
      }

      todo
    }
    Error(reason) -> todo
  }
}

// TODO just pass blobs into the execute.files function
fn perform_effect(effect, root) -> a {
  todo
}

/// A span carrying its source-of-truth.
pub type Source {
  Text(code: String, span: location.Span)
  Json
}

pub type Location {
  Location(Source)
}

// TODO extract Source from loam Source. 
fn parse(code: String) {
  case json.parse(code, dag_json.decoder(Location(Json))) {
    Ok(source) -> Ok(source)
    Error(_) ->
      case parser.all_from_string(code) {
        Ok(source) -> {
          let source =
            ir.map_annotation(source, fn(span) { Location(Text(code, span)) })
          Ok(source)
        }
        Error(reason) -> Error(parser.format_error(reason, code))
      }
  }
}

// Don't use execute.block as that is a beam assumption which is fine but not for the durable runtime

pub fn execute(session_id, seq, code) {
  use events <- result.try(load_session(session_id))
  use state <- result.try(fold_events(events, cache.ready()))
  // lookup existing session by session id

  // If the state has no running code then start running it.
  // otherwise return error

  // uses the same logic for writing an execute effect and running effects
  todo
}

fn fold_events(events: b, cache: cache.Cache(a)) -> Result(b, c) {
  // returns an error for corrupted events, needs to load file system at each point
  todo
}

fn start_session(
  trigger: Trigger,
  // box_id: Int,
  box_sequence: BoxSequence,
) -> Result(Event, d) {
  // This inserts a row in the session table and a session event using the created session_id
  let event =
    Event(
      session: "TODO new session id",
      sequence: 0,
      recorded_at: "TODO now",
      payload: Trigger(trigger:, at: box_sequence),
    )
  Ok(event)
}

fn load_session(session_id: a) -> Result(b, c) {
  // Load all the events of a session from it's session_id
  todo
}

fn load_box(box_id: a) -> Result(#(Int, v1.Cid), String) {
  // This goes to the database and look up the latest box event by box ID
  // TODO store real
  let stored = mfs.identify(mfs.Directory([]))
  Ok(#(0, stored.cid))
}
