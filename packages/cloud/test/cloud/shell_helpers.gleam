//// Shells for tests, turns are run directly and journals are exported through the API.

import cloud/apex/context.{type Context}
import cloud/box
import cloud/data/db
import cloud/data/shells
import cloud/helpers
import cloud/registry
import cloud/shells/turn
import gleam/http
import gleam/list
import gleam/option.{Some}
import howdy/testing as simulate
import pog

/// A shell in a new box called "home".
pub fn shell(context: Context) {
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Ok(pog.Returned(rows: [shell], ..)) =
    db.execute(shells.create(home.id, shells.Anyone), context.db)
  shell
}

pub fn entries(context: Context, shell: shells.Shell) {
  let assert Ok(history) = turn.history(context, shell.id)
  list.map(history, fn(entry) { entry.1 })
}

pub fn process(context: Context, shell: shells.Shell) {
  registry.lookup(context.shells, shell.id, fn() { registry.serve(Nil) })
}

pub fn run(context, shell, code) {
  registry.call(process(context, shell), 10_000, fn(_) {
    #(Nil, turn.run(context, shell, code))
  })
}

pub fn export(context, shell: shells.Shell) {
  simulate.request(http.Get, "/shells/" <> shell.id <> "/events")
  |> helpers.dispatch(context)
  |> simulate.text
}

/// A new shell in the same box with the first `length` entries of the shell's journal,
/// as if the shell had stopped there.
pub fn prefix(context: Context, shell: shells.Shell, length: Int) {
  let assert Ok(pog.Returned(rows: [copy], ..)) =
    db.execute(shells.create(shell.box, shells.Anyone), context.db)
  let copy_entries =
    "INSERT INTO journal (shell, box, seq, start, entry, recorded_at)
    SELECT $2, box, seq, start, entry, recorded_at FROM journal WHERE shell = $1 AND seq <= $3"
    |> pog.query()
    |> pog.parameter(pog.text(shell.id))
    |> pog.parameter(pog.text(copy.id))
    |> pog.parameter(pog.int(length))
  let assert Ok(_) = db.execute(copy_entries, context.db)
  copy
}
