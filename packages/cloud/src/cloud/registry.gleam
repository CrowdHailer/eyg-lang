//// Find the one process for a name, starting it if it is not running.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

pub type Message(m) {
  Lookup(name: String, start: fn() -> Subject(m), reply: Subject(Subject(m)))
}

pub type Registry(m) =
  Subject(Message(m))

pub fn start() -> actor.StartResult(Registry(m)) {
  actor.new(dict.new())
  |> actor.on_message(handle)
  |> actor.start
}

/// `start` runs in the registry, so no two processes are started for a name.
pub fn lookup(
  registry: Registry(m),
  name: String,
  start: fn() -> Subject(m),
) -> Subject(m) {
  process.call(registry, 30_000, Lookup(name, start, _))
}

fn handle(running: Dict(String, Subject(m)), message: Message(m)) {
  let Lookup(name, start, reply) = message
  let alive =
    dict.get(running, name)
    |> result.try(fn(subject) {
      use pid <- result.try(process.subject_owner(subject))
      case process.is_alive(pid) {
        True -> Ok(subject)
        False -> Error(Nil)
      }
    })
  let subject = case alive {
    Ok(subject) -> subject
    Error(Nil) -> {
      let subject = start()
      // A process that stops does not stop the registry.
      let _ = result.map(process.subject_owner(subject), process.unlink)
      subject
    }
  }
  process.send(reply, subject)
  actor.continue(dict.insert(running, name, subject))
}

/// A process that runs functions on its state one at a time.
pub fn serve(state: s) -> Subject(fn(s) -> s) {
  let assert Ok(started) =
    actor.new(state)
    |> actor.on_message(fn(state, then) { actor.continue(then(state)) })
    |> actor.start
  started.data
}

/// Run `then` in the process, nothing else runs there until it returns.
pub fn call(
  process: Subject(fn(s) -> s),
  timeout: Int,
  then: fn(s) -> #(s, a),
) -> a {
  process.call(process, timeout, fn(reply) {
    fn(state) {
      let #(state, value) = then(state)
      process.send(reply, value)
      state
    }
  })
}
