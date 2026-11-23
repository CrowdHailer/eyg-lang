import cloud/apex/context.{type Context, Context, Open}
import cloud/beam/execute
import cloud/box
import cloud/data/db
import cloud/data/shells
import cloud/file_system
import cloud/helpers
import cloud/registry
import cloud/server
import cloud/shell_helpers
import cloud/shells/event
import cloud/shells/turn
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
import howdy/testing as simulate
import pog
import unixfs/check

// Start a turn and wait until its request to /slow has arrived.
fn start_request(context, shell, code) {
  let arrived = process.new_subject()
  let server = server.start(arrived)
  let done = process.new_subject()
  process.spawn_unlinked(fn() {
    process.send(done, shell_helpers.run(context, shell, code(server)))
  })
  let assert Ok(release) = process.receive(arrived, 5000)
  #(server, release, done)
}

fn stop_during_request(context, shell, code) {
  let #(server, _release, _done) = start_request(context, shell, code)
  let assert Ok(pid) =
    process.subject_owner(shell_helpers.process(context, shell))
  process.kill(pid)
  server
}

const write =
  "perform WriteFile({path: \"/a.txt\", contents: !string_to_binary(\"a\")})"

const read = "perform ReadFile({path: \"/a.txt\", offset: 0, limit: 10})"

pub fn record_entries_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let server = server.start(process.new_subject())
  let code =
    "let n = perform Random(10)\nlet _ = "
    <> write
    <> "\nlet _ = "
    <> server.fetch(server, "GET", "/hello")
    <> "\nn"
  let assert Ok(#(Ok(value), [])) = shell_helpers.run(context, shell, code)
  let assert [
    event.Input(event.Started(..), 1, start),
    event.Output(
      [event.Answered(execute.Number(number))],
      event.Requested(_),
      written,
      event.Merged,
    ),
    event.Input(event.Continued(execute.Fetched(Ok(_))), 2, after),
    event.Output([], event.Finished(Ok(finished), []), end, event.Unchanged),
  ] = shell_helpers.entries(context, shell)
  assert int.to_string(number) == value
  assert value == finished
  assert start != written
  assert written == after
  assert written == end
}

pub fn box_changes_while_waiting_for_a_response_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let #(_server, release, done) =
    start_request(context, shell, fn(server) {
      "let _ = " <> server.fetch(server, "GET", "/slow") <> "\n" <> read
    })
  let assert Ok(other) =
    box.change(context, shell.box, fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })
  process.send(release, Nil)
  let assert Ok(Ok(#(Ok(value), _))) = process.receive(done, 5000)
  // The code continues from the latest root after the response.
  assert string.contains(value, "b3RoZXI=")
  let assert [_, _, event.Input(root: after, ..), _] =
    shell_helpers.entries(context, shell)
  assert other.root == after
}

pub fn box_changes_while_sleeping_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let done = process.new_subject()
  process.spawn(fn() {
    let code = "let _ = perform Sleep(500)\n" <> read
    process.send(done, shell_helpers.run(context, shell, code))
  })
  process.sleep(100)
  // The box is not held while the shell sleeps.
  let assert Ok(other) =
    box.change(context, shell.box, fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })
  let assert Ok(Ok(#(Ok(value), _))) = process.receive(done, 5000)
  assert string.contains(value, "b3RoZXI=")
  let assert [
    _,
    event.Output(stop: event.Slept(500), ..),
    event.Input(event.Continued(execute.Slept), _, after),
    _,
  ] = shell_helpers.entries(context, shell)
  assert other.root == after
}

pub fn send_get_again_after_stopping_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let server =
    stop_during_request(context, shell, fn(server) {
      server.fetch(server, "GET", "/slow")
    })
  let assert [_, event.Output(stop: event.Requested(..), ..)] =
    shell_helpers.entries(context, shell)
  let assert Ok(#(Ok("2"), [])) = shell_helpers.run(context, shell, "2")
  assert 2 == server.count_requests(server, http.Get, "/slow")
  let assert [
    _,
    _,
    event.Input(event.Continued(_), ..),
    event.Output(stop: event.Finished(Ok(value), _), ..),
    ..
  ] = shell_helpers.entries(context, shell)
  assert string.starts_with(value, "Ok(")
}

pub fn fail_post_after_stopping_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let server =
    stop_during_request(context, shell, fn(server) {
      server.fetch(server, "POST", "/slow")
    })
  let assert Ok(#(Ok("2"), [])) = shell_helpers.run(context, shell, "2")
  // The request might have been received so it is not sent again.
  assert 1 == server.count_requests(server, http.Post, "/slow")
  let assert [_, _, _, event.Output(stop: event.Finished(Ok(value), _), ..), ..] =
    shell_helpers.entries(context, shell)
  assert string.starts_with(value, "Error(\"network error")
}

pub fn replay_recorded_answers_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let _ =
    stop_during_request(context, shell, fn(server) {
      "let n = perform Random(1000000)\nlet _ = "
      <> server.fetch(server, "GET", "/slow")
      <> "\nn"
    })
  let assert [
    _,
    event.Output(answers: [event.Answered(execute.Number(number))], ..),
  ] = shell_helpers.entries(context, shell)
  let assert Ok(_) = shell_helpers.run(context, shell, "1")
  let assert [_, _, _, event.Output(stop: event.Finished(Ok(value), _), ..), ..] =
    shell_helpers.entries(context, shell)
  assert int.to_string(number) == value
}

fn turns(context, shell: shells.Shell) {
  simulate.request(http.Get, "/shells/" <> shell.id)
  |> helpers.dispatch(context)
  |> simulate.text
  |> json.parse(decode.at(["turns"], decode.dynamic))
}

pub fn export_every_entry_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let server = server.start(process.new_subject())
  let _ =
    shell_helpers.run(
      context,
      shell,
      "let _ = " <> write <> "\nperform Random(100)",
    )
  let _ =
    shell_helpers.run(
      context,
      shell,
      "let _ = perform Flip({})\n" <> server.fetch(server, "GET", "/hello"),
    )
  let _ = shell_helpers.run(context, shell, "!int_add(1, \"two\")")
  let _ = shell_helpers.run(context, shell, read)
  let log = shell_helpers.export(context, shell)
  assert 4 == list.length(string.split(log, "\"trigger\":\"started\"")) - 1
  let lines = string.split(string.trim(log), "\n")
  assert list.length(shell_helpers.entries(context, shell))
    == list.length(lines)
  let assert Ok(turns) = turns(context, shell)
  let assert Ok(turns) = decode.run(turns, decode.list(decode.dynamic))
  assert 4 == list.length(turns)
}

// Change a recorded answer, so the code no longer does what the journal says.
fn tamper(context: Context, shell: shells.Shell, seq, number) {
  let update =
    "UPDATE journal SET entry = jsonb_set(entry, '{answers,0,number}', to_jsonb($3::INT))
    WHERE shell = $1 AND seq = $2"
    |> pog.query()
    |> pog.parameter(pog.text(shell.id))
    |> pog.parameter(pog.int(seq))
    |> pog.parameter(pog.int(number))
  let assert Ok(_) = db.execute(update, context.db)
}

pub fn fail_to_replay_a_journal_that_does_not_match_test() {
  // The test reads while the shell writes, which one connection can not do.
  let context = helpers.pool_context()
  let assert Ok(home) = box.create(context, Some(helpers.unique("tamper")))
  let assert Ok(pog.Returned(rows: [shell], ..)) =
    db.execute(shells.create(home.id, shells.Anyone), context.db)
  // How long the code sleeps depends on the random number.
  process.spawn_unlinked(fn() {
    shell_helpers.run(
      context,
      shell,
      "let n = perform Random(1000)\nlet _ = perform Sleep(!int_add(n, 60000))\nn",
    )
  })
  helpers.wait_until(
    fn() { list.length(shell_helpers.entries(context, shell)) == 2 },
    200,
  )
  let assert Ok(pid) =
    process.subject_owner(shell_helpers.process(context, shell))
  process.kill(pid)
  let assert [
    _,
    event.Output(answers: [event.Answered(execute.Number(number))], ..),
  ] = shell_helpers.entries(context, shell)
  let _ = tamper(context, shell, 2, number + 1)
  let assert Error(box.Failed(reason)) = shell_helpers.run(context, shell, "1")
  assert reason == "the shell journal does not match the code"
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
  let shell = shell_helpers.shell(context)
  let _ =
    stop_during_request(context, shell, fn(server) {
      "let _ = " <> server.fetch(server, "GET", "/slow") <> "\n" <> write
    })
  let context = Context(..context, policy: deny_writes)
  let assert Ok(#(Ok(denied), [])) = shell_helpers.run(context, shell, write)
  // The unfinished turn ran with the policy it started with.
  let assert [
    _,
    _,
    _,
    event.Output(stop: event.Finished(Ok(allowed), _), ..),
    ..
  ] = shell_helpers.entries(context, shell)
  assert "Ok({})" == allowed
  assert "Error(\"denied\")" == denied
}

pub fn secrets_are_fingerprinted_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let assert Ok(Nil) = box.set_secret(context, shell.box, "KEY", "s3cr3t-value")
  let _ =
    stop_during_request(context, shell, fn(server) {
      "let key = perform Env(\"KEY\")\nlet _ = "
      <> server.fetch(server, "GET", "/slow")
      <> "\nkey"
    })
  let assert [_, event.Output(answers: [event.Read("KEY", _)], ..)] =
    shell_helpers.entries(context, shell)
  assert !string.contains(shell_helpers.export(context, shell), "s3cr3t")

  let assert Ok(Nil) = box.set_secret(context, shell.box, "KEY", "other")
  let assert Error(box.Failed(reason)) = shell_helpers.run(context, shell, "1")
  assert reason == "the secret KEY has changed since the turn ran"

  let assert Ok(Nil) = box.set_secret(context, shell.box, "KEY", "s3cr3t-value")
  let assert Ok(_) = shell_helpers.run(context, shell, "1")
  let assert [_, _, _, event.Output(stop: event.Finished(Ok(value), _), ..), ..] =
    shell_helpers.entries(context, shell)
  assert "Some(\"s3cr3t-value\")" == value
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

pub fn reading_shells_do_not_wait_for_the_box_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let server = server.start(process.new_subject())
  let release = hold_box(context, shell.box)
  let code = "let _ = " <> server.fetch(server, "GET", "/hello") <> "\n" <> read
  let assert Ok(#(Ok(value), [])) = shell_helpers.run(context, shell, code)
  assert string.starts_with(value, "Error(")
  process.send(release, Nil)
}

pub fn reject_a_conflicting_shell_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let server = server.start(process.new_subject())
  let release = hold_box(context, shell.box)
  // This change waits for the box process first.
  process.spawn(fn() {
    box.change(context, shell.box, fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })
  })
  process.sleep(100)
  let done = process.new_subject()
  process.spawn(fn() {
    let code =
      "let _ = " <> write <> "\n" <> server.fetch(server, "GET", "/hello")
    process.send(done, shell_helpers.run(context, shell, code))
  })
  process.sleep(100)
  process.send(release, Nil)
  let assert Ok(Ok(#(Error(reason), []))) = process.receive(done, 5000)
  assert reason == "File changes conflict\n/a.txt"
  // The request is not made when the changes before it are rejected.
  assert 0 == server.count_requests(server, http.Get, "/hello")
}

pub fn record_a_change_with_its_output_test() {
  // The test reads while the shell and box processes write, which one connection can not do.
  let context = helpers.pool_context()
  let assert Ok(home) = box.create(context, Some(helpers.unique("once")))
  let name = home.id
  let assert Ok(pog.Returned(rows: [shell], ..)) =
    db.execute(shells.create(name, shells.Anyone), context.db)
  let server = server.start(process.new_subject())
  let release = hold_box(context, name)
  process.spawn_unlinked(fn() {
    let code =
      "let _ = "
      <> write
      <> "\nlet _ = "
      <> server.fetch(server, "GET", "/hello")
      <> "\n2"
    shell_helpers.run(context, shell, code)
  })
  // The shell stops while its change waits to be merged.
  helpers.wait_until(
    fn() { list.length(shell_helpers.entries(context, shell)) == 1 },
    200,
  )
  process.sleep(50)
  let assert Ok(pid) =
    process.subject_owner(shell_helpers.process(context, shell))
  process.kill(pid)
  // The box merges the change and records the shell's output with it.
  process.send(release, Nil)
  helpers.wait_until(
    fn() {
      case shell_helpers.entries(context, shell) {
        [_, event.Output(stop: event.Requested(..), change: event.Merged, ..)] ->
          True
        _ -> False
      }
    },
    200,
  )
  let assert Ok(merged) = box.latest(context, name)
  assert 2 == merged.sequence
  // Another change to the same file after the shell's change was merged.
  let assert Ok(_) =
    box.change(context, name, fn(root) {
      file_system.write(root, "/a.txt", <<"other">>)
    })

  let assert Ok(#(Ok("1"), [])) = shell_helpers.run(context, shell, "1")
  // The turn continued from its recorded output, the request was only sent then.
  let assert [
    _,
    _,
    event.Input(event.Continued(_), ..),
    event.Output(stop: event.Finished(Ok(_), _), ..),
    ..
  ] = shell_helpers.entries(context, shell)
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
  let shell = shell_helpers.shell(context)
  let _ =
    stop_during_request(context, shell, fn(server) {
      "let x = @lib\nlet _ = " <> server.fetch(server, "GET", "/slow") <> "\nx"
    })
  let assert [
    _,
    event.Output(
      answers: [event.Pinned("lib", None, _)],
      stop: event.Requested(..),
      ..,
    ),
  ] = shell_helpers.entries(context, shell)

  // A new version of the package is released before the shell resumes.
  let cache = server.release(context.state.cache, "lib", "2")
  let context = Context(..context, state: execute.State(..state, cache:))
  let assert Ok(#(Ok("2"), [])) = shell_helpers.run(context, shell, "@lib")
  // The turn that stopped finished with the version it started with.
  let assert Ok(value) =
    list.find_map(shell_helpers.entries(context, shell), fn(entry) {
      case entry {
        event.Output(stop: event.Finished(Ok(value), _), ..) -> Ok(value)
        _ -> Error(Nil)
      }
    })
  assert "1" == value
}

pub fn fork_a_shell_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let _ =
    stop_during_request(context, shell, fn(server) {
      "let _ = " <> write <> "\n" <> server.fetch(server, "GET", "/slow")
    })
  let response =
    simulate.request(http.Post, "/shells/" <> shell.id <> "/fork")
    |> helpers.dispatch(context)
  assert 201 == response.status
  let assert Ok(id) =
    json.parse(simulate.text(response), decode.at(["id"], decode.string))
  let assert Ok(pog.Returned(rows: [fork], ..)) =
    db.execute(shells.get(id), context.db)
  // A fork has a copy of the journal.
  assert shell_helpers.entries(context, shell)
    == shell_helpers.entries(context, fork)

  // Both continue the unfinished turn, its change is merged once.
  let assert Ok(_) = shell_helpers.run(context, shell, "1")
  let assert Ok(_) = shell_helpers.run(context, fork, "2")
  let assert Ok(home) = box.latest(context, shell.box)
  assert 2 == home.sequence
  let original = shell_helpers.entries(context, shell)
  let forked = shell_helpers.entries(context, fork)
  assert list.take(original, 2) == list.take(forked, 2)
  assert original != forked
}

pub fn run_a_built_program_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let assert Ok(source) = parser.all_from_string("!int_add(1, 2)")
  let program = ir.map_annotation(source, fn(_) { Nil })
  let assert Ok(#(Ok("3"), [])) =
    shell_helpers.turn(context, shell, turn.Program(program))
  let assert [event.Input(event.Submitted(recorded, _), ..), ..] =
    shell_helpers.entries(context, shell)
  assert recorded == program
}

pub fn cancel_a_running_turn_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let #(server, release, _done) =
    start_request(context, shell, fn(server) {
      "let _ = "
      <> write
      <> "\nlet _ = "
      <> server.fetch(server, "GET", "/slow")
      <> "\n1"
    })
  let assert Ok(Nil) = turn.cancel(context, shell)
  process.send(release, Nil)
  let assert [
    event.Input(event.Started(..), ..),
    event.Output(stop: event.Requested(..), ..),
    event.Input(event.Cancelled, ..),
  ] = shell_helpers.entries(context, shell)
  // The cancelled turn is not resumed, its request is not sent again.
  let assert Ok(#(Ok("2"), [])) = shell_helpers.run(context, shell, "2")
  assert 1 == server.count_requests(server, http.Get, "/slow")
  // The change made before the request was merged and is kept.
  let assert Ok(#(Ok(value), [])) = shell_helpers.run(context, shell, read)
  assert string.starts_with(value, "Ok(")
}

pub fn resume_a_stopped_turn_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let server =
    stop_during_request(context, shell, fn(server) {
      server.fetch(server, "GET", "/slow")
    })
  let assert Ok(Nil) = turn.resume(context, shell)
  let assert [
    _,
    _,
    event.Input(event.Continued(_), ..),
    event.Output(stop: event.Finished(Ok(_), _), ..),
  ] = shell_helpers.entries(context, shell)
  assert 2 == server.count_requests(server, http.Get, "/slow")
  // Nothing is left to resume.
  let assert Ok(Nil) = turn.resume(context, shell)
}

pub fn write_a_skill_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let code =
    "let _ = perform MakeDirectory(\"/skills/greet\")
perform WriteFile({path: \"/skills/greet/SKILL.md\", contents: !string_to_binary(\"---\\nname: greet\\n---\")})"
  let assert Ok(#(Ok("Ok({})"), [])) = shell_helpers.run(context, shell, code)
  let assert Ok(home) = box.latest(context, shell.box)
  let assert Ok(Ok(<<"---\nname: greet\n---">>)) =
    execute.files(
      file_system.read(home.root, "/skills/greet/SKILL.md"),
      context.state,
    )
}
