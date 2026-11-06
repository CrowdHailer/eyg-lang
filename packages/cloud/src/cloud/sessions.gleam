//// Every shell session and its full history, held by one process.
////
//// A session is a list of steps. Each step records the input, the output
//// and the snapshot (scope and file system root) after it ran.
//// Forking copies the steps up to a point into a new session,
//// so the fork starts with exactly that scope and file system.

import cloud/code
import cloud/shell.{type Output, type Snapshot}
import cloud/store.{type Store}
import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import gleam/string
import gleam/time/timestamp
import morph/editable as e

pub type Step {
  Step(command: Command, output: List(Output), snapshot: Snapshot, at: Int)
}

/// What a step did.
pub type Command {
  /// Code that was run. The first step of a session is `Code(Vacant)`.
  Code(source: e.Expression)
}

/// A short description of a command, on one line.
pub fn describe(command: Command) -> String {
  case command {
    Code(source) ->
      case string.split(code.to_text(source), "\n") {
        [line, ..] -> line
        [] -> ""
      }
  }
}

/// Where a fork came from: a session and the index of a step in it.
pub type Origin {
  Origin(session: String, step: Int)
}

pub type Session {
  Session(
    id: String,
    created: Int,
    origin: Option(Origin),
    /// Oldest first. The first step is the empty starting state.
    steps: List(Step),
  )
}

pub type Event {
  Changed(Session)
}

pub opaque type Message {
  Create(reply: Subject(Session))
  Get(id: String, reply: Subject(Result(Session, Nil)))
  All(reply: Subject(List(Session)))
  Append(id: String, step: Step, reply: Subject(Result(Session, Nil)))
  Fork(id: String, step: Int, reply: Subject(Result(Session, Nil)))
  Subscribe(Subject(Event))
  Unsubscribe(Subject(Event))
}

pub opaque type Sessions {
  Sessions(subject: Subject(Message), store: Store)
}

type State {
  State(
    store: Store,
    sessions: Dict(String, Session),
    subscribers: List(Subject(Event)),
  )
}

const timeout = 5000

/// Start the registry. The block store is created by, and lives as long as,
/// the calling process.
pub fn start() -> Result(Sessions, actor.StartError) {
  let store = store.new()
  let started =
    actor.new(State(store:, sessions: dict.new(), subscribers: []))
    |> actor.on_message(handle)
    |> actor.start
  case started {
    Ok(actor.Started(data: subject, ..)) -> Ok(Sessions(subject:, store:))
    Error(reason) -> Error(reason)
  }
}

pub fn store(sessions: Sessions) -> Store {
  sessions.store
}

pub fn create(sessions: Sessions) -> Session {
  process.call(sessions.subject, timeout, Create)
}

pub fn get(sessions: Sessions, id: String) -> Result(Session, Nil) {
  process.call(sessions.subject, timeout, Get(id, _))
}

/// All sessions, most recently created first.
pub fn all(sessions: Sessions) -> List(Session) {
  process.call(sessions.subject, timeout, All)
}

pub fn append(
  sessions: Sessions,
  id: String,
  step: Step,
) -> Result(Session, Nil) {
  process.call(sessions.subject, timeout, Append(id, step, _))
}

/// Start a new session from the state after step `step` of session `id`.
pub fn fork(sessions: Sessions, id: String, step: Int) -> Result(Session, Nil) {
  process.call(sessions.subject, timeout, Fork(id, step, _))
}

/// Receive an event every time a session is created or changed.
pub fn subscribe(sessions: Sessions, subscriber: Subject(Event)) -> Nil {
  process.send(sessions.subject, Subscribe(subscriber))
}

pub fn unsubscribe(sessions: Sessions, subscriber: Subject(Event)) -> Nil {
  process.send(sessions.subject, Unsubscribe(subscriber))
}

/// The snapshot after the last step.
pub fn current(session: Session) -> Snapshot {
  let assert Ok(step) = list.last(session.steps)
  step.snapshot
}

/// The number of commands run, not counting the starting state.
pub fn commands(session: Session) -> Int {
  list.length(session.steps) - 1
}

/// A short description: the first command run in the session.
/// For a fork that is the first command run after forking.
pub fn title(session: Session) -> String {
  let inherited = case session.origin {
    Some(origin) -> origin.step + 1
    None -> 1
  }
  case list.drop(session.steps, inherited), session.origin {
    [first, ..], _ -> describe(first.command)
    [], Some(origin) -> "fork of " <> origin.session
    [], None -> "new session"
  }
}

pub fn now() -> Int {
  let #(seconds, nanoseconds) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  seconds * 1000 + nanoseconds / 1_000_000
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Create(reply) -> {
      let start = Step(Code(e.Vacant), [], shell.start(state.store), now())
      let session = new_session(state, None, [start])
      process.send(reply, session)
      actor.continue(save(state, session))
    }
    Get(id, reply) -> {
      process.send(reply, dict.get(state.sessions, id))
      actor.continue(state)
    }
    All(reply) -> {
      dict.values(state.sessions)
      |> list.sort(compare_newest)
      |> process.send(reply, _)
      actor.continue(state)
    }
    Append(id, step, reply) ->
      case dict.get(state.sessions, id) {
        Ok(session) -> {
          let session =
            Session(..session, steps: list.append(session.steps, [step]))
          process.send(reply, Ok(session))
          actor.continue(save(state, session))
        }
        Error(Nil) -> {
          process.send(reply, Error(Nil))
          actor.continue(state)
        }
      }
    Fork(id, index, reply) ->
      case dict.get(state.sessions, id) {
        Ok(source) if index >= 0 -> {
          let steps = list.take(source.steps, index + 1)
          use <- fail_unless(list.length(steps) == index + 1, reply, state)
          let session = new_session(state, Some(Origin(id, index)), steps)
          process.send(reply, Ok(session))
          actor.continue(save(state, session))
        }
        _ -> {
          process.send(reply, Error(Nil))
          actor.continue(state)
        }
      }
    Subscribe(subscriber) ->
      actor.continue(
        State(..state, subscribers: [subscriber, ..state.subscribers]),
      )
    Unsubscribe(subscriber) ->
      actor.continue(
        State(
          ..state,
          subscribers: list.filter(state.subscribers, fn(s) { s != subscriber }),
        ),
      )
  }
}

fn compare_newest(a: Session, b: Session) -> order.Order {
  int.compare(b.created, a.created)
  |> order.break_tie(string.compare(b.id, a.id))
}

fn new_session(state: State, origin, steps) -> Session {
  let id = unique_id(state.sessions)
  Session(id:, created: now(), origin:, steps:)
}

fn save(state: State, session: Session) -> State {
  // Subscribers are not removed when they exit, so drop them here.
  let subscribers = list.filter(state.subscribers, is_alive)
  list.each(subscribers, process.send(_, Changed(session)))
  State(
    ..state,
    sessions: dict.insert(state.sessions, session.id, session),
    subscribers:,
  )
}

fn is_alive(subject) {
  case process.subject_owner(subject) {
    Ok(pid) -> process.is_alive(pid)
    Error(Nil) -> False
  }
}

fn unique_id(existing) -> String {
  let id =
    crypto.strong_random_bytes(5)
    |> bit_array.base16_encode
    |> string.lowercase
  case dict.has_key(existing, id) {
    True -> unique_id(existing)
    False -> id
  }
}

fn fail_unless(check, reply, state, then) {
  case check {
    True -> then()
    False -> {
      process.send(reply, Error(Nil))
      actor.continue(state)
    }
  }
}
