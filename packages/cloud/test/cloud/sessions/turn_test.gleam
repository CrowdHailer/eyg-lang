import cloud/apex/context.{type Context, Context, Open}
import cloud/beam/execute
import cloud/box
import cloud/data/db
import cloud/data/sessions
import cloud/file_system
import cloud/helpers
import cloud/registry
import cloud/server
import cloud/sessions/event
import cloud/sessions/turn
import eyg/hub/cache
import gleam/dict
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import pog
import unixfs/check

fn session(context: Context) {
  let assert Ok(_) = box.create(context, "home")
  let assert Ok(pog.Returned(rows: [session], ..)) =
    db.execute(sessions.create("home", None), context.db)
  session
}

fn events(context: Context, session: sessions.Session) {
  let assert Ok(history) = turn.history(context, session.id)
  list.map(history, fn(entry) { entry.2 })
}

fn process(context: Context, session: sessions.Session) {
  registry.lookup(context.sessions, session.id, fn() { registry.serve(Nil) })
}

fn run(context, session, code) {
  registry.call(process(context, session), 10_000, fn(_) {
    #(Nil, turn.run(context, session, code))
  })
}

// Start a turn and wait until its request to /slow has arrived.
fn start_request(context, session, code) {
  let arrived = process.new_subject()
  let server = server.start(arrived)
  let done = process.new_subject()
  process.spawn_unlinked(fn() {
    process.send(done, run(context, session, code(server)))
  })
  let assert Ok(release) = process.receive(arrived, 5000)
  #(server, release, done)
}

fn stop_during_request(context, session, code) {
  let #(server, _release, _done) = start_request(context, session, code)
  let assert Ok(pid) = process.subject_owner(process(context, session))
  process.kill(pid)
  server
}

const write =
  "perform WriteFile({path: \"/a.txt\", contents: !string_to_binary(\"a\")})"

const read = "perform ReadFile({path: \"/a.txt\", offset: 0, limit: 10})"

pub fn record_events_test() {
  use context <- helpers.context()
  let session = session(context)
  let server = server.start(process.new_subject())
  let code =
    "let n = perform Random(10)\nlet _ = "
    <> write
    <> "\nlet _ = "
    <> server.fetch(server, "GET", "/hello")
    <> "\nn"
  let assert Ok(#(Ok(value), [])) = run(context, session, code)
  let assert [
    event.Started(..),
    event.Resumed(start),
    event.Answered(execute.Number(number)),
    event.Requested(_, written),
    event.Answered(execute.Fetched(Ok(_))),
    event.Resumed(after),
    event.Returned(Ok(_), [], _),
    event.Finished(Ok(finished), [], end),
  ] = events(context, session)
  assert int.to_string(number) == value
  assert value == finished
  assert start != written
  assert written == after
  assert written == end
}

pub fn box_changes_while_waiting_for_a_response_test() {
  use context <- helpers.context()
  let session = session(context)
  let #(_server, release, done) =
    start_request(context, session, fn(server) {
      "let _ = " <> server.fetch(server, "GET", "/slow") <> "\n" <> read
    })
  let assert Ok(other) =
    box.change(context, "home", fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })
  process.send(release, Nil)
  let assert Ok(Ok(#(Ok(value), _))) = process.receive(done, 5000)
  // The code continues from the latest root after the response.
  assert string.contains(value, "b3RoZXI=")
  let assert [_, _, _, _, event.Resumed(after), _, _] = events(context, session)
  assert other.root == after
}

pub fn box_changes_while_sleeping_test() {
  use context <- helpers.context()
  let session = session(context)
  let done = process.new_subject()
  process.spawn(fn() {
    let code = "let _ = perform Sleep(500)\n" <> read
    process.send(done, run(context, session, code))
  })
  process.sleep(100)
  // The box is not held while the session sleeps.
  let assert Ok(other) =
    box.change(context, "home", fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })
  let assert Ok(Ok(#(Ok(value), _))) = process.receive(done, 5000)
  assert string.contains(value, "b3RoZXI=")
  let assert [_, _, event.Slept(500, _), event.Resumed(after), _, _] =
    events(context, session)
  assert other.root == after
}

pub fn send_get_again_after_stopping_test() {
  use context <- helpers.context()
  let session = session(context)
  let server =
    stop_during_request(context, session, fn(server) {
      server.fetch(server, "GET", "/slow")
    })
  let assert [_, _, event.Requested(..)] = events(context, session)
  let assert Ok(#(Ok("2"), [])) = run(context, session, "2")
  assert 2 == server.count_requests(server, http.Get, "/slow")
  let assert [
    _,
    _,
    _,
    event.Answered(_),
    _,
    _,
    event.Finished(Ok(value), _, _),
    ..
  ] = events(context, session)
  assert string.starts_with(value, "Ok(")
}

pub fn fail_post_after_stopping_test() {
  use context <- helpers.context()
  let session = session(context)
  let server =
    stop_during_request(context, session, fn(server) {
      server.fetch(server, "POST", "/slow")
    })
  let assert Ok(#(Ok("2"), [])) = run(context, session, "2")
  // The request might have been received so it is not sent again.
  assert 1 == server.count_requests(server, http.Post, "/slow")
  let assert [_, _, _, _, _, _, event.Finished(Ok(value), _, _), ..] =
    events(context, session)
  assert string.starts_with(value, "Error(\"network error")
}

pub fn replay_recorded_answers_test() {
  use context <- helpers.context()
  let session = session(context)
  let _ =
    stop_during_request(context, session, fn(server) {
      "let n = perform Random(1000000)\nlet _ = "
      <> server.fetch(server, "GET", "/slow")
      <> "\nn"
    })
  let assert [_, _, event.Answered(execute.Number(number)), _] =
    events(context, session)
  let assert Ok(_) = run(context, session, "1")
  let assert [_, _, _, _, _, _, _, event.Finished(Ok(value), _, _), ..] =
    events(context, session)
  assert int.to_string(number) == value
}

const deny_writes =
  "let pass = (input) -> { Pass(input) }
{
  append_file: pass,
  cwd: pass,
  delete_file: pass,
  env: pass,
  fetch: pass,
  flip: pass,
  make_directory: pass,
  now: pass,
  random: pass,
  read_directory: pass,
  read_file: pass,
  sleep: pass,
  standard_error: pass,
  standard_out: pass,
  write_file: (_) -> { Mock(Error(\"denied\")) }
}"

pub fn replay_with_the_policy_a_turn_started_with_test() {
  use context <- helpers.context()
  let session = session(context)
  let _ =
    stop_during_request(context, session, fn(server) {
      "let _ = " <> server.fetch(server, "GET", "/slow") <> "\n" <> write
    })
  let context = Context(..context, policy: deny_writes)
  let assert Ok(#(Ok(denied), [])) = run(context, session, write)
  // The unfinished turn ran with the policy it started with.
  let assert [_, _, _, _, _, _, event.Finished(Ok(allowed), _, _), ..] =
    events(context, session)
  assert "Ok({})" == allowed
  assert "Error(\"denied\")" == denied
}

pub fn secrets_are_fingerprinted_test() {
  use context <- helpers.context()
  let secrets = dict.from_list([#("KEY", "s3cr3t-value")])
  let context =
    Context(..context, state: execute.State(..context.state, secrets:))
  let session = session(context)
  let _ =
    stop_during_request(context, session, fn(server) {
      "let key = perform Env(\"KEY\")\nlet _ = "
      <> server.fetch(server, "GET", "/slow")
      <> "\nkey"
    })
  let assert [_, _, event.Read("KEY", _), _] = events(context, session)
  let recorded =
    events(context, session)
    |> list.map(fn(event) { json.to_string(event.encode(event)) })
    |> string.concat
  assert !string.contains(recorded, "s3cr3t")

  let changed = dict.from_list([#("KEY", "other")])
  let changed =
    Context(..context, state: execute.State(..context.state, secrets: changed))
  let assert Error(box.Failed(reason)) = run(changed, session, "1")
  assert reason == "the secret KEY has changed since the turn ran"

  let assert Ok(_) = run(context, session, "1")
  let assert [_, _, _, _, _, _, _, event.Finished(Ok(value), _, _), ..] =
    events(context, session)
  assert "Some(\"s3cr3t-value\")" == value
}

// Keep the box process busy until the returned subject is sent to.
fn hold_box(context: Context, name) {
  let assert Ok(home) = box.latest(context, name)
  let process =
    registry.lookup(context.boxes, name, fn() {
      registry.serve(Open(home, check.empty()))
    })
  let held = process.new_subject()
  process.spawn(fn() {
    registry.call(process, 10_000, fn(open) {
      let release = process.new_subject()
      process.send(held, release)
      let _ = process.receive(release, 10_000)
      #(open, Nil)
    })
  })
  let assert Ok(release) = process.receive(held, 1000)
  release
}

pub fn reading_sessions_do_not_wait_for_the_box_test() {
  use context <- helpers.context()
  let session = session(context)
  let server = server.start(process.new_subject())
  let release = hold_box(context, "home")
  let code = "let _ = " <> server.fetch(server, "GET", "/hello") <> "\n" <> read
  let assert Ok(#(Ok(value), [])) = run(context, session, code)
  assert string.starts_with(value, "Error(")
  process.send(release, Nil)
}

pub fn reject_a_conflicting_session_test() {
  use context <- helpers.context()
  let session = session(context)
  let server = server.start(process.new_subject())
  let release = hold_box(context, "home")
  // This change waits for the box process first.
  process.spawn(fn() {
    box.change(context, "home", fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })
  })
  process.sleep(100)
  let done = process.new_subject()
  process.spawn(fn() {
    let code =
      "let _ = " <> write <> "\n" <> server.fetch(server, "GET", "/hello")
    process.send(done, run(context, session, code))
  })
  process.sleep(100)
  process.send(release, Nil)
  let assert Ok(Ok(#(Error(reason), []))) = process.receive(done, 5000)
  assert reason == "File changes conflict\n/a.txt"
  // The request is not made when the changes before it are rejected.
  assert 0 == server.count_requests(server, http.Get, "/hello")
}

fn wait_until(check, attempts) {
  case check(), attempts {
    True, _ -> Nil
    False, 0 -> panic as "timed out waiting"
    False, _ -> {
      process.sleep(10)
      wait_until(check, attempts - 1)
    }
  }
}

pub fn merge_a_change_only_once_test() {
  // The test reads while the session and box processes write, which one connection can not do.
  let context = helpers.pool_context()
  let name = helpers.unique("once")
  let assert Ok(_) = box.create(context, name)
  let assert Ok(Nil) = box.durable(context, name)
  let assert Ok(pog.Returned(rows: [session], ..)) =
    db.execute(sessions.create(name, None), context.db)
  let server = server.start(process.new_subject())
  let release = hold_box(context, name)
  process.spawn_unlinked(fn() {
    let code =
      "let _ = "
      <> write
      <> "\nlet _ = "
      <> server.fetch(server, "GET", "/hello")
      <> "\n2"
    run(context, session, code)
  })
  // The session stops after recording its events, while its change waits to be merged.
  wait_until(
    fn() {
      list.any(events(context, session), fn(event) {
        case event {
          event.Requested(..) -> True
          _ -> False
        }
      })
    },
    200,
  )
  process.sleep(50)
  let assert Ok(pid) = process.subject_owner(process(context, session))
  process.kill(pid)
  let assert Ok(before) = box.latest(context, name)
  process.send(release, Nil)
  wait_until(
    fn() {
      let assert Ok(latest) = box.latest(context, name)
      latest.sequence > before.sequence
    },
    200,
  )
  // Another change to the same file after the session's change was merged.
  let assert Ok(_) =
    box.change(context, name, fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })

  let assert Ok(#(Ok("1"), [])) = run(context, session, "1")
  // Merging the session's change again did nothing, so it did not conflict.
  let assert [_, _, _, event.Answered(_), _, _, event.Finished(Ok(_), _, _), ..] =
    events(context, session)
  assert 1 == server.count_requests(server, http.Get, "/hello")
  let assert Ok(latest) = box.latest(context, name)
  assert Ok(Ok(<<"other">>))
    == execute.files(file_system.read(latest.root, "/a.txt"), context.state)
}

pub fn replay_with_the_packages_a_turn_resolved_test() {
  use context <- helpers.context()
  let hub = server.start(process.new_subject())
  let cache = server.release(cache.empty(), "lib", "1")
  let state = execute.State(..context.state, origin: server.origin(hub), cache:)
  let context = Context(..context, state:)
  let session = session(context)
  let _ =
    stop_during_request(context, session, fn(server) {
      "let x = @lib\nlet _ = " <> server.fetch(server, "GET", "/slow") <> "\nx"
    })
  let assert [_, _, event.Pinned("lib", None, _), event.Requested(..)] =
    events(context, session)

  // A new version of the package is released before the session resumes.
  let cache = server.release(context.state.cache, "lib", "2")
  let context = Context(..context, state: execute.State(..state, cache:))
  let assert Ok(#(Ok("2"), [])) = run(context, session, "@lib")
  // The turn that stopped finished with the version it started with.
  let assert Ok(value) =
    list.find_map(events(context, session), fn(event) {
      case event {
        event.Finished(Ok(value), _, _) -> Ok(value)
        _ -> Error(Nil)
      }
    })
  assert "1" == value
}
