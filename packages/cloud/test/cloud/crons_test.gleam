import cloud/beam/execute
import cloud/box
import cloud/crons
import cloud/file_system
import cloud/helpers
import cloud/session_helpers
import cloud/sessions/turn
import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleam/time/duration
import gleam/time/timestamp

// A configuration with a cron for each name, schedule and the body of its run function.
fn config(crons: List(#(String, String, String))) {
  let fields =
    list.map(crons, fn(cron) {
      let #(name, schedule, body) = cron
      name
      <> ": {schedule: \""
      <> schedule
      <> "\", run: (_) -> { "
      <> body
      <> " }}"
    })
  "{crons: {" <> string.join(fields, ", ") <> "}}"
}

fn write_crons(context, box, crons) {
  write_config(context, box, config(crons))
}

fn write_config(context, box, text) {
  let assert Ok(box) =
    box.change(context, box, fn(root) {
      file_system.write(root, crons.config, <<text:utf8>>)
    })
  box
}

// 20 seconds after half past nine, UTC.
fn at(minutes) {
  timestamp.from_unix_seconds(1_795_426_220)
  |> timestamp.add(duration.minutes(minutes))
}

pub fn read_config_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  // A new box has a configuration without crons.
  assert Ok([]) == crons.read(home.root, context.state)
  let home =
    write_crons(context, home.id, [
      #("b", "0 8 * * *", "1"),
      #("a", "* * * * *", "2"),
    ])
  assert Ok([crons.Cron("a", "* * * * *"), crons.Cron("b", "0 8 * * *")])
    == crons.read(home.root, context.state)
  assert "let {crons} = import \"./_box/config.eyg\"\ncrons.a.run({})"
    == crons.code(crons.Cron("a", "* * * * *"))
  // A configuration without crons, or that does not say when a cron runs.
  let home = write_config(context, home.id, "{}")
  assert Ok([]) == crons.read(home.root, context.state)
  let home = write_config(context, home.id, "{crons: {a: {run: (_) -> { 1 }}}}")
  let assert Error(_) = crons.read(home.root, context.state)
  // A box without a configuration has no crons.
  let assert Ok(home) =
    box.change(context, home.id, fn(root) {
      file_system.delete(root, crons.config)
    })
  assert Ok([]) == crons.read(home.root, context.state)
}

pub fn next_test() {
  // The next whole hour after 09:30:20.
  assert crons.next("0 * * * *", at(0))
    == Ok(timestamp.from_unix_seconds(1_795_428_000))
  let assert Error(_) = crons.next("every day", at(0))
}

pub fn run_once_when_due_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  // A box without crons.
  assert Ok([]) == crons.due(context, home, at(0))

  let home = write_crons(context, home.id, [#("each", "*/10 * * * *", "1")])
  // A new cron first runs at the next time its schedule matches.
  assert Ok([]) == crons.due(context, home, at(0))
  assert Ok([]) == crons.due(context, home, at(5))
  let assert Ok([crons.Run(cron: crons.Cron(name: "each", ..), session:, ..)]) =
    crons.due(context, home, at(10))
  // A run is claimed once.
  assert Ok([]) == crons.due(context, home, at(10))
  // A run that was missed runs once.
  assert Ok([
      crons.Run(home.id, crons.Cron("each", "*/10 * * * *"), session),
    ])
    == crons.due(context, home, at(45))
  assert Ok([]) == crons.due(context, home, at(45))

  // A changed schedule starts again from its next match, in the same session.
  let home = write_crons(context, home.id, [#("each", "0 * * * *", "2")])
  assert Ok([]) == crons.due(context, home, at(46))
  assert Ok([]) == crons.due(context, home, at(50))
  assert Ok([crons.Run(home.id, crons.Cron("each", "0 * * * *"), session)])
    == crons.due(context, home, at(90))

  let home = write_crons(context, home.id, [#("bad", "never", "1")])
  let assert Error(_) = crons.due(context, home, at(90))
}

pub fn run_code_in_the_box_test() {
  let context = helpers.pool_context()
  let assert Ok(home) = box.create(context, Some(helpers.unique("crons")))
  let code =
    "perform WriteFile({path: \"/ran.txt\", contents: !string_to_binary(\"ran\")})"
  let _ = write_crons(context, home.id, [#("write", "* * * * *", code)])
  crons.tick(context, at(0))
  crons.tick(context, at(1))
  let assert Ok(home) = wait(context, home.id, 50)
  assert Ok(Ok(<<"ran">>))
    == execute.files(file_system.read(home.root, "/ran.txt"), context.state)
  // The turn is in the cron's session in the box.
  let assert Ok([crons.Run(session:, ..)]) = crons.due(context, home, at(2))
  let assert Ok(session) = turn.find(context, session)
  assert session_helpers.events(context, session) != []
}

// The box once the cron has written its file.
fn wait(context, id, tries) {
  let assert Ok(home) = box.latest(context, id)
  case
    execute.files(file_system.read(home.root, "/ran.txt"), context.state),
    tries
  {
    Ok(Ok(_)), _ -> Ok(home)
    _, 0 -> Error(Nil)
    _, _ -> {
      process.sleep(100)
      wait(context, id, tries - 1)
    }
  }
}
