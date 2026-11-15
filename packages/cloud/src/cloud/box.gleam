//// One owner serializes and durably publishes a box's checked roots.

import clockwork
import cloud/beam/execute
import cloud/beam/file_system
import cloud/box/check
import cloud/box/interface
import cloud/box/session
import cloud/box/store
import cloud/box/transaction as tx
import cloud/content
import cloud/overlay
import cloud/schedule
import eyg/interpreter/state as value
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/time/timestamp
import multiformats/cid/v1
import simplifile

pub type Message {
  Stage(codec: Int, bytes: BitArray, reply: Subject(Result(v1.Cid, String)))
  Inspect(reply: Subject(store.Snapshot))
  Invoke(
    path: String,
    input: value.Value(execute.Meta),
    reply: Subject(Result(value.Value(execute.Meta), String)),
  )
  Tick
  Connect(
    config: String,
    identity: String,
    text: String,
    agent: overlay.Session,
    reply: Subject(Result(String, String)),
  )
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
    subject: Subject(Message),
    deadlines: Dict(String, #(String, Int)),
  )
}

pub fn start(path: String, initial: store.Snapshot, runtime: execute.State) {
  actor.new_with_initialiser(30_000, fn(subject) {
    let snapshot = case simplifile.is_file(path) {
      Ok(True) -> store.load(path)
      Ok(False) -> Ok(initial)
      Error(error) -> Error(simplifile.describe_error(error))
    }
    use snapshot <- result.try(snapshot)
    use #(modules, runtime) <- result.try(check.validate(
      snapshot.files,
      runtime,
    ))
    use runtime <- result.try(interface.validate(modules, runtime))
    use _ <- result.try(store.save(path, snapshot))
    let _ = process.send_after(subject, 1000, Tick)
    Ok(
      actor.initialised(State(
        path,
        snapshot,
        modules,
        runtime,
        subject,
        dict.new(),
      ))
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

pub fn invoke(box, path, input) {
  process.call(box, 30_000, Invoke(path, input, _))
}

pub fn connect(box, config, identity, text, agent) {
  process.call_forever(box, Connect(config, identity, text, agent, _))
}

pub fn stage(box, codec, bytes) {
  process.call(box, 30_000, Stage(codec, bytes, _))
}

fn publish(state: State, files) {
  publish_if(state, files, fn() { True })
}

fn publish_if(state: State, files, authorized) {
  use #(modules, runtime) <- result.try(check.validate(files, state.runtime))
  use runtime <- result.try(interface.validate(modules, runtime))
  use _ <- result.try(case authorized() {
    True -> Ok(Nil)
    False -> Error("Authorization changed before publication")
  })
  let snapshot =
    store.Snapshot(files, [state.snapshot.files.root, ..state.snapshot.history])
  use _ <- result.map(store.save(state.path, snapshot))
  State(..state, snapshot:, modules:, runtime:)
}

fn run(state: State, path, input) {
  let config = {
    use module <- result.try(
      dict.get(state.modules, path)
      |> result.replace_error("Interface not configured: " <> path),
    )
    interface.decode(module.value)
  }
  case config {
    Error(error) -> #(Error(error), state)
    Ok(config) -> {
      // The owner cannot process a policy update between effects. Thus this
      // committed policy remains current for the entire invocation.
      let #(outcome, runtime, files) =
        execute.call_value(
          config.handler,
          input,
          state.runtime,
          config.policy,
          state.snapshot.files,
          fn(_) { Nil },
        )
      let state = State(..state, runtime:)
      let committed = case outcome {
        Ok(_) -> publish(state, files)
        Error(_) -> Ok(state)
      }
      let #(outcome, state) = case committed {
        Ok(updated) -> #(outcome, updated)
        Error(reason) -> #(Error(reason), state)
      }
      let status = case outcome {
        Ok(_) -> "ok"
        Error(reason) -> reason
      }
      let now =
        timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time()).0
      let trace =
        json.object([
          #("interface", json.string(path)),
          #("time", json.int(now)),
          #("outcome", json.string(status)),
        ])
        |> json.to_string
        |> bit_array.from_string
      let id =
        int.to_string(now)
        <> "-"
        <> bit_array.base64_url_encode(crypto.strong_random_bytes(9), False)
      let traced =
        tx.prepare(
          state.snapshot.files,
          state.snapshot.files.root,
          [
            tx.MakeDirectory("/traces"),
            tx.Put("/traces/" <> id <> ".json", trace),
          ],
          fn(_) { True },
        )
        |> result.map_error(fn(_) { "Unable to record trace" })
        |> result.try(publish(state, _))
      case traced {
        Ok(state) -> #(outcome, state)
        Error(reason) -> #(Error(reason), state)
      }
    }
  }
}

fn tick(state: State) {
  let now = timestamp.system_time()
  let seconds = timestamp.to_unix_seconds_and_nanoseconds(now).0
  let crons = interface.crons(state.modules)
  let state =
    State(
      ..state,
      deadlines: dict.filter(state.deadlines, fn(name, _) {
        list.any(crons, fn(cron) { cron.name == name })
      }),
    )
  list.fold(crons, state, fn(state, cron) {
    let assert Ok(parsed) = clockwork.from_string(cron.expression)
    let next = fn() {
      timestamp.to_unix_seconds_and_nanoseconds(schedule.next_occurrence(
        parsed,
        now,
      )).0
    }
    case dict.get(state.deadlines, cron.name) {
      Ok(#(expression, due))
        if expression == cron.expression && due <= seconds
      -> {
        let #(_, state) = run(state, cron.name, v.unit())
        State(
          ..state,
          deadlines: dict.insert(state.deadlines, cron.name, #(
            cron.expression,
            next(),
          )),
        )
      }
      Ok(#(expression, _)) if expression == cron.expression -> state
      _ ->
        State(
          ..state,
          deadlines: dict.insert(state.deadlines, cron.name, #(
            cron.expression,
            next(),
          )),
        )
    }
  })
}

fn handle(state: State, message: Message) {
  case message {
    Stage(codec, bytes, reply) -> {
      let staged = {
        use _ <- result.try(content.source(codec, bytes))
        let cid = content.identify(codec, bytes)
        let files =
          file_system.State(
            ..state.snapshot.files,
            content: dict.insert(state.snapshot.files.content, cid, bytes),
          )
        let snapshot = store.Snapshot(..state.snapshot, files:)
        use _ <- result.map(store.save(state.path, snapshot))
        #(cid, State(..state, snapshot:))
      }
      case staged {
        Ok(#(cid, state)) -> {
          process.send(reply, Ok(cid))
          actor.continue(state)
        }
        Error(error) -> {
          process.send(reply, Error(error))
          actor.continue(state)
        }
      }
    }
    Connect(config, identity, text, agent, reply) -> {
      let outcome = {
        use module <- result.try(
          dict.get(state.modules, config)
          |> result.replace_error("Connection is not configured"),
        )
        use #(text, runtime, files) <- result.try(session.run(
          module,
          identity,
          text,
          agent,
          state.runtime,
          state.snapshot.files,
        ))
        use state <- result.map(publish(State(..state, runtime:), files))
        #(text, state)
      }
      case outcome {
        Ok(#(text, state)) -> {
          process.send(reply, Ok(text))
          actor.continue(state)
        }
        Error(error) -> {
          process.send(reply, Error(error))
          actor.continue(state)
        }
      }
    }
    Tick -> {
      let state = tick(state)
      let _ = process.send_after(state.subject, 1000, Tick)
      actor.continue(state)
    }
    Invoke(path, input, reply) -> {
      let #(outcome, state) = run(state, path, input)
      process.send(reply, outcome)
      actor.continue(state)
    }
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
        publish_if(state, files, fn() {
          list.all(changes, fn(change) {
            case tx.canonical(change) {
              Ok(change) -> authorize(change)
              Error(_) -> False
            }
          })
        })
        |> result.map_error(tx.Invalid)
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
