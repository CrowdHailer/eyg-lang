//// Crons run code in a named box on a schedule.
////
//// A box's crons are in its `/_box/config.eyg` module, so they are changed as any other file, by a session in the box,
//// and the box only accepts them if they type check. The module is a record, its `crons` field has a field for each cron.
//// A cron is a record with a `schedule` in cron syntax in UTC, and a `run` function that is called with an empty record.
////
//// ```eyg
//// {crons: {hacker_news: {schedule: "7 8 * * *", run: import "../hn.eyg"}}}
//// ```
////
//// Each cron runs as a turn in its own session in the box, which is made the first time the cron is seen.
//// Its history is in that session, and a turn that stopped part way is finished before the next one.
////
//// A cron first runs at the next time its schedule matches. When the service was stopped at that time it runs
//// once when it starts again, runs that were missed are not made up.
//// Transient boxes have no crons, they are copies and would run their box's crons again.

import clockwork
import cloud/apex/context.{type Context}
import cloud/beam/execute
import cloud/box
import cloud/data/boxes.{type Box}
import cloud/data/crons
import cloud/data/db
import cloud/sessions/turn
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import gleam/dict
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/order
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import multiformats/cid/v1
import pog
import simplifile
import unixfs/mfs

/// The module that configures a box.
pub const config = "/_box/config.eyg"

pub type Cron {
  Cron(name: String, schedule: String)
}

/// The code of a turn that runs the cron.
pub fn code(cron: Cron) -> String {
  "let {crons} = import \"."
  <> config
  <> "\"\ncrons."
  <> cron.name
  <> ".run({})"
}

/// The crons configured in the box at `root`, a box without a configuration has none.
pub fn read(root: v1.Cid, state: execute.State) -> Result(List(Cron), String) {
  let path = string.split(config, "/") |> list.drop(1)
  case execute.files(mfs.read(root, path), state) {
    Ok(Error(simplifile.Enoent)) -> Ok([])
    Ok(Error(reason)) -> Error(simplifile.describe_error(reason))
    Error(reason) -> Error(reason)
    Ok(Ok(_)) -> {
      let #(value, _state) = execute.module(config, state, root)
      result.try(value, configured)
    }
  }
}

fn configured(value) {
  let crons = case value {
    v.Record(fields) -> dict.get(fields, "crons")
    _ -> Error(Nil)
  }
  case crons {
    Error(Nil) -> Ok([])
    Ok(v.Record(crons)) ->
      dict.to_list(crons)
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.try_map(fn(entry) {
        case entry.1 {
          v.Record(cron) ->
            case dict.get(cron, "schedule") {
              Ok(v.String(schedule)) -> Ok(Cron(entry.0, schedule))
              _ -> Error("the cron " <> entry.0 <> " has no schedule")
            }
          _ -> Error("the cron " <> entry.0 <> " is not a record")
        }
      })
    Ok(other) -> Error("crons is not a record " <> simple_debug.inspect(other))
  }
}

/// The first time after `now` that the schedule matches, on a whole minute.
pub fn next(schedule: String, now: Timestamp) -> Result(Timestamp, String) {
  use cron <- result.map(
    clockwork.from_string(schedule)
    |> result.replace_error("invalid schedule " <> schedule),
  )
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(now)
  let minute = timestamp.from_unix_seconds(seconds - seconds % 60)
  clockwork.next_occurrence(cron, minute, duration.seconds(0))
}

/// A cron of a box that is due, and the session it runs in.
pub type Run {
  Run(box: String, cron: Cron, session: String)
}

/// The crons of the box that are due at `now`. Each due run is claimed, so it is returned once.
/// A cron that is new or whose schedule changed is set to run next at its schedule.
pub fn due(
  context: Context,
  box: Box,
  now: Timestamp,
) -> Result(List(Run), String) {
  use crons <- result.try(read(box.root, context.state))
  list.try_map(crons, fn(cron) {
    use next <- result.try(
      next(cron.schedule, now)
      |> result.map_error(fn(reason) { cron.name <> ": " <> reason }),
    )
    use found <- result.try(query(context, crons.get(box.id, cron.name)))
    case found {
      [] -> {
        use session <- result.try(
          turn.start(context, box.id, None)
          |> result.map_error(string.inspect),
        )
        let insert =
          crons.insert(box.id, cron.name, cron.schedule, session.id, next)
        use _ <- result.map(query(context, insert))
        []
      }
      [crons.Cron(schedule:, session:, next_run:), ..] -> {
        let changed = schedule != cron.schedule
        let is_due = timestamp.compare(next_run, now) != order.Gt
        case changed || is_due {
          False -> Ok([])
          True -> {
            let claim =
              crons.claim(box.id, cron.name, next_run, cron.schedule, next)
            use claimed <- result.map(query(context, claim))
            case claimed, changed {
              [_], False -> [Run(box.id, cron, session)]
              _, _ -> []
            }
          }
        }
      }
    }
  })
  |> result.map(list.flatten)
}

fn query(context: Context, query) {
  db.execute(query, context.db)
  |> result.map(fn(returned: pog.Returned(_)) { returned.rows })
  |> result.map_error(string.inspect)
}

/// Run the crons of every named box that are due at `now`, each in a process of its own.
pub fn tick(context: Context, now: Timestamp) -> Nil {
  case box.named(context) {
    Ok(boxes) ->
      list.each(boxes, fn(named) {
        case due(context, named, now) {
          Ok(runs) -> list.each(runs, run(context, _))
          Error(reason) ->
            io.println_error("crons of " <> named.id <> ": " <> reason)
        }
      })
    Error(reason) -> io.println_error("crons: " <> string.inspect(reason))
  }
}

fn run(context: Context, run: Run) {
  process.spawn_unlinked(fn() {
    let outcome = {
      use session <- result.try(turn.find(context, run.session))
      turn.send(context, session, turn.Code(code(run.cron)))
    }
    case outcome {
      Ok(_) -> Nil
      Error(reason) ->
        io.println_error(
          "cron " <> run.cron.name <> " failed: " <> string.inspect(reason),
        )
    }
  })
}

pub opaque type Message {
  Tick
}

/// Check the crons of every named box each minute.
pub fn start(context: Context) {
  actor.new_with_initialiser(1000, fn(subject) {
    process.send(subject, Tick)
    actor.initialised(subject) |> actor.returning(subject) |> Ok
  })
  |> actor.on_message(fn(subject, _tick) {
    tick(context, timestamp.system_time())
    process.send_after(subject, 60_000, Tick)
    actor.continue(subject)
  })
  |> actor.start
}
