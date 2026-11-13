//// UTC cron triggers. Execute a function, then send its result as a session message.

import clockwork
import cloud/beam/execute
import cloud/beam/file_system
import cloud/schedule/message
import cloud/session
import cloud/trigger
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/order
import gleam/otp/actor
import gleam/result
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import simplifile

pub type Config {
  Config(name: String, cron: String, code: String)
}

pub type Schedule {
  Schedule(
    name: String,
    cron: clockwork.Cron,
    function: trigger.Checked,
    next: Timestamp,
  )
}

pub type Message {
  Tick
}

pub type Runtime {
  Runtime(state: execute.State, policy: execute.Policy)
}

pub fn runtime(state: execute.State) -> Result(Runtime, String) {
  use code <- result.try(
    simplifile.read("policy.eyg") |> result.map_error(simplifile.describe_error),
  )
  let #(policy, state) = execute.load_policy(code, state)
  result.map(policy, fn(policy) { Runtime(state, policy) })
}

type State {
  State(
    schedules: List(Schedule),
    sessions: Subject(session.Message),
    subject: Subject(Message),
    runtime: Runtime,
  )
}

pub fn prepare(
  configs: List(Config),
  now: Timestamp,
  state: execute.State,
) -> Result(#(List(Schedule), execute.State), String) {
  use #(schedules, state) <- result.map(
    list.try_fold(configs, #([], state), fn(acc, config) {
      let #(schedules, state) = acc
      use cron <- result.try(
        clockwork.from_string(config.cron)
        |> result.replace_error(
          "Schedule " <> config.name <> ": invalid cron " <> config.cron,
        ),
      )
      use #(functions, state) <- result.map(trigger.prepare_returning(
        [#(config.name, config.code)],
        t.unit,
        message.type_(),
        state,
      ))
      let assert [function] = functions
      #(
        [
          Schedule(config.name, cron, function, next_occurrence(cron, now)),
          ..schedules
        ],
        state,
      )
    }),
  )
  #(list.reverse(schedules), state)
}

pub fn next_occurrence(cron: clockwork.Cron, now: Timestamp) -> Timestamp {
  // Clockwork rounds second 59 up before advancing; give it a minute boundary
  // so a trigger due in the next second is not skipped.
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(now)
  let minute = timestamp.from_unix_seconds(seconds - seconds % 60)
  clockwork.next_occurrence(cron, minute, duration.seconds(0))
}

pub fn start(
  schedules: List(Schedule),
  sessions: Subject(session.Message),
  runtime: Runtime,
) {
  actor.new_with_initialiser(1000, fn(subject) {
    process.send(subject, Tick)
    actor.initialised(State(schedules, sessions, subject, runtime))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(fn(state, _) {
    let #(schedules, runtime) =
      dispatch_due(
        state.schedules,
        timestamp.system_time(),
        state.sessions,
        state.runtime,
      )
    let _ = process.send_after(state.subject, 1000, Tick)
    actor.continue(State(..state, schedules:, runtime:))
  })
  |> actor.start
}

/// Queue a configured action immediately without changing its cron deadline.
pub fn trigger_named(
  schedules: List(Schedule),
  name: String,
  sessions: Subject(session.Message),
  runtime: Runtime,
) -> #(Result(Nil, String), Runtime) {
  case list.find(schedules, fn(schedule) { schedule.name == name }) {
    Error(_) -> #(Error("Unknown cron action: " <> name), runtime)
    Ok(schedule) -> {
      let #(message, runtime) = run(schedule, runtime)
      #(result.map(message, process.send(sessions, _)), runtime)
    }
  }
}

/// Scheduled output is deliberately silent. The agent must send replies using tools.
pub fn run(
  schedule: Schedule,
  runtime: Runtime,
) -> #(Result(session.Message, String), Runtime) {
  let print = fn(_) { Nil }
  let #(outcome, state, _) =
    execute.call_value(
      schedule.function,
      v.unit(),
      runtime.state,
      runtime.policy,
      file_system.new(dict.new()),
      print,
    )
  let message = {
    use message <- result.map(result.try(outcome, message.decode))
    let payload = case message.payload {
      message.Code(code) -> session.Code(code)
      message.Text(text) ->
        session.UserPrompt("[Schedule: " <> schedule.name <> "]\n" <> text)
    }
    session.Message(message.session_id, payload, print)
  }
  #(message, Runtime(..runtime, state:))
}

/// Queue each due schedule once, then advance past now (no catch-up burst).
pub fn dispatch_due(
  schedules: List(Schedule),
  now: Timestamp,
  sessions: Subject(session.Message),
  runtime: Runtime,
) -> #(List(Schedule), Runtime) {
  let #(schedules, runtime) =
    list.fold(schedules, #([], runtime), fn(acc, schedule) {
      let #(schedules, runtime) = acc
      case timestamp.compare(schedule.next, now) {
        order.Gt -> #([schedule, ..schedules], runtime)
        _ -> {
          let #(message, runtime) = run(schedule, runtime)
          case message {
            Ok(message) -> process.send(sessions, message)
            Error(reason) ->
              io.println_error(
                "Schedule " <> schedule.name <> " failed: " <> reason,
              )
          }
          #(
            [
              Schedule(..schedule, next: next_occurrence(schedule.cron, now)),
              ..schedules
            ],
            runtime,
          )
        }
      }
    })
  #(list.reverse(schedules), runtime)
}
