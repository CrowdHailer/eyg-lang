import cloud/sessions.{Origin, Step}
import cloud/shell
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}

fn run(registry, session: sessions.Session, code) {
  let store = sessions.store(registry)
  let assert Ok(source) = shell.parse(code)
  let #(output, snapshot) = shell.run(store, source, sessions.current(session))
  let assert Ok(session) =
    sessions.append(
      registry,
      session.id,
      Step(sessions.Code(source), output, snapshot, 0),
    )
  session
}

pub fn create_session_test() {
  let assert Ok(registry) = sessions.start()
  let session = sessions.create(registry)
  assert session.origin == None
  assert sessions.commands(session) == 0
  assert sessions.title(session) == "new session"
  assert sessions.get(registry, session.id) == Ok(session)
}

pub fn append_steps_test() {
  let assert Ok(registry) = sessions.start()
  let session = sessions.create(registry)
  let session = run(registry, session, "let x = 1")
  let session = run(registry, session, "x")
  assert sessions.commands(session) == 2
  assert sessions.title(session) == "let x = 1"
  assert sessions.get(registry, session.id) == Ok(session)
}

pub fn fork_restores_state_at_step_test() {
  let assert Ok(registry) = sessions.start()
  let session = sessions.create(registry)
  let session = run(registry, session, "let x = 1")
  let session = run(registry, session, "let x = 2")
  let assert Ok(fork) = sessions.fork(registry, session.id, 1)
  assert fork.id != session.id
  assert fork.origin == Some(Origin(session.id, 1))
  assert sessions.commands(fork) == 1
  let fork = run(registry, fork, "x")
  let assert Ok(last) = list.last(fork.steps)
  assert last.output == [shell.Result("1")]
  // The original is unchanged
  assert sessions.get(registry, session.id) == Ok(session)
}

pub fn fork_out_of_range_test() {
  let assert Ok(registry) = sessions.start()
  let session = sessions.create(registry)
  assert sessions.fork(registry, session.id, 1) == Error(Nil)
  assert sessions.fork(registry, session.id, -1) == Error(Nil)
  assert sessions.fork(registry, "missing", 0) == Error(Nil)
}

pub fn all_newest_first_test() {
  let assert Ok(registry) = sessions.start()
  let first = sessions.create(registry)
  process.sleep(2)
  let second = sessions.create(registry)
  assert list.map(sessions.all(registry), fn(s) { s.id })
    == [second.id, first.id]
}

pub fn subscribers_hear_changes_test() {
  let assert Ok(registry) = sessions.start()
  let events = process.new_subject()
  sessions.subscribe(registry, events)
  let session = sessions.create(registry)
  assert process.receive(events, 100) == Ok(sessions.Changed(session))
}

pub fn fork_title_test() {
  let assert Ok(registry) = sessions.start()
  let session = sessions.create(registry)
  let session = run(registry, session, "let x = 1")
  let assert Ok(fork) = sessions.fork(registry, session.id, 1)
  assert sessions.title(fork) == "fork of " <> session.id
  let fork = run(registry, fork, "x")
  assert sessions.title(fork) == "x"
}
