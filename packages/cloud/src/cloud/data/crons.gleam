//// When each cron of a box runs next, and the shell it runs in.

import gleam/dynamic/decode
import gleam/time/timestamp.{type Timestamp}
import pog

pub type Cron {
  Cron(schedule: String, shell: String, next_run: Timestamp)
}

fn cron() {
  use schedule <- decode.field(0, decode.string)
  use shell <- decode.field(1, decode.string)
  use next_run <- decode.field(2, decode.int)
  decode.success(Cron(
    schedule:,
    shell:,
    next_run: timestamp.from_unix_seconds(next_run),
  ))
}

// Times are whole seconds.
fn seconds(time: Timestamp) {
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(time)
  pog.int(seconds)
}

pub fn get(box: String, name: String) -> pog.Query(Cron) {
  "SELECT schedule, shell, next_run FROM crons WHERE box = $1 AND name = $2"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.text(name))
  |> pog.returning(cron())
}

/// Add a cron, nothing is changed if the box already has one with the name.
pub fn insert(
  box: String,
  name: String,
  schedule: String,
  shell: String,
  next_run: Timestamp,
) -> pog.Query(Nil) {
  "INSERT INTO crons (box, name, schedule, shell, next_run) VALUES ($1, $2, $3, $4, $5)
  ON CONFLICT (box, name) DO NOTHING"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.text(name))
  |> pog.parameter(pog.text(schedule))
  |> pog.parameter(pog.text(shell))
  |> pog.parameter(seconds(next_run))
}

/// Move the next run of a cron from `due` to `next`, returning a row only if it was still due.
/// Of the processes that claim a run at the same time only one gets the row.
pub fn claim(
  box: String,
  name: String,
  due: Timestamp,
  schedule: String,
  next: Timestamp,
) -> pog.Query(Nil) {
  "UPDATE crons SET next_run = $5, schedule = $4
  WHERE box = $1 AND name = $2 AND next_run = $3
  RETURNING box"
  |> pog.query()
  |> pog.parameter(pog.text(box))
  |> pog.parameter(pog.text(name))
  |> pog.parameter(seconds(due))
  |> pog.parameter(pog.text(schedule))
  |> pog.parameter(seconds(next))
  |> pog.returning(decode.success(Nil))
}
