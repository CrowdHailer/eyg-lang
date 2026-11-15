//// One owner serializes and durably publishes a box's checked roots.

import cloud/beam/execute
import cloud/beam/file_system
import cloud/box/check
import cloud/box/store
import cloud/box/transaction as tx
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import multiformats/cid/v1
import simplifile

pub type Message {
  Inspect(reply: Subject(store.Snapshot))
  Commit(
    base: v1.Cid,
    changes: List(tx.Change),
    authorize: fn(tx.Change) -> Bool,
    reply: Subject(Result(v1.Cid, tx.Error)),
  )
}

type State {
  State(
    path: String,
    snapshot: store.Snapshot,
    modules: Dict(String, check.Module),
    runtime: execute.State,
  )
}

pub fn start(path: String, initial: store.Snapshot, runtime: execute.State) {
  actor.new_with_initialiser(30_000, fn(subject) {
    let snapshot = case simplifile.is_file(path) {
      Ok(True) -> store.load(path)
      _ -> store.save(path, initial) |> result.replace(initial)
    }
    use snapshot <- result.try(snapshot)
    use #(modules, runtime) <- result.try(check.validate(
      snapshot.files,
      runtime,
    ))
    Ok(
      actor.initialised(State(path, snapshot, modules, runtime))
      |> actor.returning(subject),
    )
  })
  |> actor.on_message(handle)
  |> actor.start
}

pub fn inspect(box: Subject(Message)) {
  process.call(box, 30_000, Inspect)
}

pub fn commit(box, base, changes, authorize) {
  process.call(box, 30_000, Commit(base, changes, authorize, _))
}

fn handle(state: State, message: Message) {
  case message {
    Inspect(reply) -> {
      process.send(reply, state.snapshot)
      actor.continue(state)
    }
    Commit(base, changes, authorize, reply) -> {
      let outcome = {
        use files <- result.try(tx.prepare(
          state.snapshot.files,
          base,
          changes,
          authorize,
        ))
        use #(modules, runtime) <- result.try(
          check.validate(files, state.runtime) |> result.map_error(tx.Invalid),
        )
        let snapshot =
          store.Snapshot(files, [
            state.snapshot.files.root,
            ..state.snapshot.history
          ])
        use _ <- result.map(
          store.save(state.path, snapshot) |> result.map_error(tx.Invalid),
        )
        State(..state, snapshot:, modules:, runtime:)
      }
      case outcome {
        Ok(updated) -> {
          process.send(reply, Ok(updated.snapshot.files.root))
          actor.continue(updated)
        }
        Error(error) -> {
          process.send(reply, Error(error))
          actor.continue(state)
        }
      }
    }
  }
}

pub fn empty() {
  store.Snapshot(file_system.new(dict.new()), [])
}
