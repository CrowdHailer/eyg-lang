import cloud/apex/context.{type Context, Context, Open}
import cloud/beam/execute
import cloud/box
import cloud/data/db
import cloud/data/sessions
import cloud/file_system
import cloud/helpers
import cloud/registry
import cloud/server
import cloud/session_helpers
import cloud/sessions/event
import cloud/sessions/turn
import eyg/hub/cache
import eyg/ir/tree as ir
import eyg/parser
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import pog
import unixfs/check
import wisp/simulate

// Start a turn and wait until its request to /slow has arrived.
fn start_request(context, session, code) {
  let arrived = process.new_subject()
  let server = server.start(arrived)
  let done = process.new_subject()
  process.spawn_unlinked(fn() {
    process.send(done, session_helpers.run(context, session, code(server)))
  })
  let assert Ok(release) = process.receive(arrived, 5000)
  #(server, release, done)
}

fn stop_during_request(context, session, code) {
  let #(server, _release, _done) = start_request(context, session, code)
  let assert Ok(pid) =
    process.subject_owner(session_helpers.process(context, session))
  process.kill(pid)
  server
}

const write =
  "perform WriteFile({path: \"/a.txt\", contents: !string_to_binary(\"a\")})"

const read = "perform ReadFile({path: \"/a.txt\", offset: 0, limit: 10})"

pub fn record_events_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let server = server.start(process.new_subject())
  let code =
    "let n = perform Random(10)\nlet _ = "
    <> write
    <> "\nlet _ = "
    <> server.fetch(server, "GET", "/hello")
    <> "\nn"
  let assert Ok(#(Ok(value), [])) = session_helpers.run(context, session, code)
  let assert [
    event.Started(..),
    event.Resumed(start),
    event.Answered(execute.Number(number)),
    event.Requested(_, written),
    event.Answered(execute.Fetched(Ok(_))),
    event.Resumed(after),
    event.Returned(Ok(_), [], _),
    event.Finished(Ok(finished), [], end),
  ] = session_helpers.events(context, session)
  assert int.to_string(number) == value
  assert value == finished
  assert start != written
  assert written == after
  assert written == end
}

pub fn box_changes_while_waiting_for_a_response_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let #(_server, release, done) =
    start_request(context, session, fn(server) {
      "let _ = " <> server.fetch(server, "GET", "/slow") <> "\n" <> read
    })
  let assert Ok(other) =
    box.change(context, session.box, fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })
  process.send(release, Nil)
  let assert Ok(Ok(#(Ok(value), _))) = process.receive(done, 5000)
  // The code continues from the latest root after the response.
  assert string.contains(value, "b3RoZXI=")
  let assert [_, _, _, _, event.Resumed(after), _, _] =
    session_helpers.events(context, session)
  assert other.root == after
}

pub fn box_changes_while_sleeping_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let done = process.new_subject()
  process.spawn(fn() {
    let code = "let _ = perform Sleep(500)\n" <> read
    process.send(done, session_helpers.run(context, session, code))
  })
  process.sleep(100)
  // The box is not held while the session sleeps.
  let assert Ok(other) =
    box.change(context, session.box, fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })
  let assert Ok(Ok(#(Ok(value), _))) = process.receive(done, 5000)
  assert string.contains(value, "b3RoZXI=")
  let assert [_, _, event.Slept(500, _), event.Resumed(after), _, _] =
    session_helpers.events(context, session)
  assert other.root == after
}

pub fn send_get_again_after_stopping_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let server =
    stop_during_request(context, session, fn(server) {
      server.fetch(server, "GET", "/slow")
    })
  let assert [_, _, event.Requested(..)] =
    session_helpers.events(context, session)
  let assert Ok(#(Ok("2"), [])) = session_helpers.run(context, session, "2")
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
  ] = session_helpers.events(context, session)
  assert string.starts_with(value, "Ok(")
}

pub fn fail_post_after_stopping_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let server =
    stop_during_request(context, session, fn(server) {
      server.fetch(server, "POST", "/slow")
    })
  let assert Ok(#(Ok("2"), [])) = session_helpers.run(context, session, "2")
  // The request might have been received so it is not sent again.
  assert 1 == server.count_requests(server, http.Post, "/slow")
  let assert [_, _, _, _, _, _, event.Finished(Ok(value), _, _), ..] =
    session_helpers.events(context, session)
  assert string.starts_with(value, "Error(\"network error")
}

pub fn replay_recorded_answers_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let _ =
    stop_during_request(context, session, fn(server) {
      "let n = perform Random(1000000)\nlet _ = "
      <> server.fetch(server, "GET", "/slow")
      <> "\nn"
    })
  let assert [_, _, event.Answered(execute.Number(number)), _] =
    session_helpers.events(context, session)
  let assert Ok(_) = session_helpers.run(context, session, "1")
  let assert [_, _, _, _, _, _, _, event.Finished(Ok(value), _, _), ..] =
    session_helpers.events(context, session)
  assert int.to_string(number) == value
}

fn turns(context, session: sessions.Session) {
  simulate.request(http.Get, "/sessions/" <> session.id)
  |> helpers.dispatch(context)
  |> simulate.read_body
  |> json.parse(decode.at(["turns"], decode.dynamic))
}

pub fn export_and_reconstruct_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let server = server.start(process.new_subject())
  let _ =
    session_helpers.run(
      context,
      session,
      "let _ = " <> write <> "\nperform Random(100)",
    )
  let _ =
    session_helpers.run(
      context,
      session,
      "let _ = perform Flip({})\n" <> server.fetch(server, "GET", "/hello"),
    )
  let _ = session_helpers.run(context, session, "!int_add(1, \"two\")")
  let _ = session_helpers.run(context, session, read)
  let log = session_helpers.export(context, session)
  assert 4 == list.length(string.split(log, "\"type\":\"started\"")) - 1

  let assert Ok(copy) = session_helpers.import_(context, session.box, log)
  assert turns(context, session) == turns(context, copy)
  assert log == session_helpers.export(context, copy)
}

pub fn resume_reconstructed_turn_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let server =
    stop_during_request(context, session, fn(server) {
      "let n = perform Random(1000000)\nlet _ = "
      <> server.fetch(server, "GET", "/slow")
      <> "\nn"
    })
  let assert Ok(copy) =
    session_helpers.import_(
      context,
      session.box,
      session_helpers.export(context, session),
    )
  let assert [_, _, event.Answered(execute.Number(number)), _] =
    session_helpers.events(context, copy)
  // The copy finishes the turn from its events.
  let assert Ok(#(Ok("\"done\""), [])) =
    session_helpers.run(context, copy, "\"done\"")
  let assert [_, _, _, _, _, _, _, event.Finished(Ok(value), _, _), ..] =
    session_helpers.events(context, copy)
  assert int.to_string(number) == value
  assert 2 == server.count_requests(server, http.Get, "/slow")
}

pub fn reject_events_that_do_not_match_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let _ = session_helpers.run(context, session, "perform Random(10)")
  let assert [_, _, event.Answered(execute.Number(number)), ..] =
    session_helpers.events(context, session)
  let changed =
    session_helpers.export(context, session)
    |> string.replace(
      "\"number\":" <> int.to_string(number),
      "\"number\":" <> int.to_string(number + 10),
    )
  assert Error(422) == session_helpers.import_(context, session.box, changed)
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
  let session = session_helpers.session(context)
  let _ =
    stop_during_request(context, session, fn(server) {
      "let _ = " <> server.fetch(server, "GET", "/slow") <> "\n" <> write
    })
  let context = Context(..context, policy: deny_writes)
  let assert Ok(#(Ok(denied), [])) =
    session_helpers.run(context, session, write)
  // The unfinished turn ran with the policy it started with.
  let assert [_, _, _, _, _, _, event.Finished(Ok(allowed), _, _), ..] =
    session_helpers.events(context, session)
  assert "Ok({})" == allowed
  assert "Error(\"denied\")" == denied
}

pub fn secrets_are_fingerprinted_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let assert Ok(Nil) =
    box.set_secret(context, session.box, "KEY", "s3cr3t-value")
  let _ =
    stop_during_request(context, session, fn(server) {
      "let key = perform Env(\"KEY\")\nlet _ = "
      <> server.fetch(server, "GET", "/slow")
      <> "\nkey"
    })
  let assert [_, _, event.Read("KEY", _), _] =
    session_helpers.events(context, session)
  assert !string.contains(session_helpers.export(context, session), "s3cr3t")

  let assert Ok(Nil) = box.set_secret(context, session.box, "KEY", "other")
  let assert Error(box.Failed(reason)) =
    session_helpers.run(context, session, "1")
  assert reason == "the secret KEY has changed since the turn ran"

  let assert Ok(Nil) =
    box.set_secret(context, session.box, "KEY", "s3cr3t-value")
  let assert Ok(_) = session_helpers.run(context, session, "1")
  let assert [_, _, _, _, _, _, _, event.Finished(Ok(value), _, _), ..] =
    session_helpers.events(context, session)
  assert "Some(\"s3cr3t-value\")" == value
}

pub fn reload_export_after_the_policy_changes_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let assert Ok(#(Ok("Ok({})"), [])) =
    session_helpers.run(context, session, write)
  let log = session_helpers.export(context, session)
  // The events record the policy each turn ran with.
  let context = Context(..context, policy: deny_writes)
  let assert Ok(copy) = session_helpers.import_(context, session.box, log)
  assert turns(context, session) == turns(context, copy)
}

// Keep the box process busy until the returned subject is sent to.
fn hold_box(context: Context, id) {
  let assert Ok(home) = box.latest(context, id)
  let process =
    registry.lookup(context.boxes, id, fn() {
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
  let session = session_helpers.session(context)
  let server = server.start(process.new_subject())
  let release = hold_box(context, session.box)
  let code = "let _ = " <> server.fetch(server, "GET", "/hello") <> "\n" <> read
  let assert Ok(#(Ok(value), [])) = session_helpers.run(context, session, code)
  assert string.starts_with(value, "Error(")
  process.send(release, Nil)
}

pub fn reject_a_conflicting_session_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let server = server.start(process.new_subject())
  let release = hold_box(context, session.box)
  // This change waits for the box process first.
  process.spawn(fn() {
    box.change(context, session.box, fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })
  })
  process.sleep(100)
  let done = process.new_subject()
  process.spawn(fn() {
    let code =
      "let _ = " <> write <> "\n" <> server.fetch(server, "GET", "/hello")
    process.send(done, session_helpers.run(context, session, code))
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
  let assert Ok(home) = box.create(context, Some(helpers.unique("once")))
  let name = home.id
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
    session_helpers.run(context, session, code)
  })
  // The session stops after recording its events, while its change waits to be merged.
  wait_until(
    fn() {
      list.any(session_helpers.events(context, session), fn(event) {
        case event {
          event.Requested(..) -> True
          _ -> False
        }
      })
    },
    200,
  )
  process.sleep(50)
  let assert Ok(pid) =
    process.subject_owner(session_helpers.process(context, session))
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

  let assert Ok(#(Ok("1"), [])) = session_helpers.run(context, session, "1")
  // Merging the session's change again did nothing, so it did not conflict.
  let assert [_, _, _, event.Answered(_), _, _, event.Finished(Ok(_), _, _), ..] =
    session_helpers.events(context, session)
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
  let session = session_helpers.session(context)
  let _ =
    stop_during_request(context, session, fn(server) {
      "let x = @lib\nlet _ = " <> server.fetch(server, "GET", "/slow") <> "\nx"
    })
  let assert [_, _, event.Pinned("lib", None, _), event.Requested(..)] =
    session_helpers.events(context, session)

  // A new version of the package is released before the session resumes.
  let cache = server.release(context.state.cache, "lib", "2")
  let context = Context(..context, state: execute.State(..state, cache:))
  let assert Ok(#(Ok("2"), [])) = session_helpers.run(context, session, "@lib")
  // The turn that stopped finished with the version it started with.
  let assert Ok(value) =
    list.find_map(session_helpers.events(context, session), fn(event) {
      case event {
        event.Finished(Ok(value), _, _) -> Ok(value)
        _ -> Error(Nil)
      }
    })
  assert "1" == value
}

pub fn fork_a_session_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let _ =
    stop_during_request(context, session, fn(server) {
      "let _ = " <> write <> "\n" <> server.fetch(server, "GET", "/slow")
    })
  let response =
    simulate.request(http.Post, "/sessions/" <> session.id <> "/fork")
    |> helpers.dispatch(context)
  assert 201 == response.status
  let assert Ok(id) =
    json.parse(simulate.read_body(response), decode.at(["id"], decode.string))
  let assert Ok(pog.Returned(rows: [fork], ..)) =
    db.execute(sessions.get(id), context.db)
  let assert Ok(pog.Returned(rows: [original], ..)) =
    db.execute(sessions.get(session.id), context.db)
  // A fork points at the same position in the thread.
  assert original.head == fork.head

  // Both continue the unfinished turn, its change is merged once.
  let assert Ok(_) = session_helpers.run(context, session, "1")
  let assert Ok(_) = session_helpers.run(context, fork, "2")
  let assert Ok(home) = box.latest(context, session.box)
  assert 2 == home.sequence
  let original = session_helpers.events(context, session)
  let forked = session_helpers.events(context, fork)
  assert list.take(original, 4) == list.take(forked, 4)
  assert original != forked
}

pub fn import_shares_the_thread_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let assert Ok(_) = session_helpers.run(context, session, write)
  let count = fn() {
    let assert Ok(pog.Returned(rows: [count], ..)) =
      pog.query("SELECT count(*)::INT FROM thread_events")
      |> pog.returning(decode.at([0], decode.int))
      |> db.execute(context.db)
    count
  }
  let before = count()
  let assert Ok(copy) =
    session_helpers.import_(
      context,
      session.box,
      session_helpers.export(context, session),
    )
  // Keys are made from the events, so the copy points at the same history.
  assert before == count()
  let assert Ok(pog.Returned(rows: [original], ..)) =
    db.execute(sessions.get(session.id), context.db)
  assert original.head == copy.head
}

pub fn run_a_built_program_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let assert Ok(source) = parser.all_from_string("!int_add(1, 2)")
  let program = ir.map_annotation(source, fn(_) { Nil })
  let assert Ok(#(Ok("3"), [])) =
    session_helpers.turn(context, session, turn.Program(program))
  let assert [event.Submitted(recorded, _), ..] =
    session_helpers.events(context, session)
  assert recorded == program
  // The program is in the export, so a copy replays it.
  let log = session_helpers.export(context, session)
  let assert Ok(copy) = session_helpers.import_(context, session.box, log)
  assert turns(context, session) == turns(context, copy)
}

pub fn cancel_a_running_turn_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let #(server, release, _done) =
    start_request(context, session, fn(server) {
      "let _ = "
      <> write
      <> "\nlet _ = "
      <> server.fetch(server, "GET", "/slow")
      <> "\n1"
    })
  let assert Ok(Nil) = turn.cancel(context, session)
  process.send(release, Nil)
  let assert [
    event.Started(..),
    event.Resumed(_),
    event.Requested(..),
    event.Finished(Error("cancelled"), [], _),
  ] = session_helpers.events(context, session)
  // The cancelled turn is not resumed, its request is not sent again.
  let assert Ok(#(Ok("2"), [])) = session_helpers.run(context, session, "2")
  assert 1 == server.count_requests(server, http.Get, "/slow")
  // The change made before the request was merged and is kept.
  let assert Ok(#(Ok(value), [])) = session_helpers.run(context, session, read)
  assert string.starts_with(value, "Ok(")
  let log = session_helpers.export(context, session)
  let assert Ok(_) = session_helpers.import_(context, session.box, log)
}

pub fn resume_a_stopped_turn_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let server =
    stop_during_request(context, session, fn(server) {
      server.fetch(server, "GET", "/slow")
    })
  let assert Ok(Nil) = turn.resume(context, session)
  let assert [_, _, _, event.Answered(_), _, _, event.Finished(Ok(_), _, _)] =
    session_helpers.events(context, session)
  assert 2 == server.count_requests(server, http.Get, "/slow")
  // Nothing is left to resume.
  let assert Ok(Nil) = turn.resume(context, session)
}
