import eyg/interpreter/value as v
import glasshouse/helpers.{sha256}
import glasshouse/journal
import glasshouse/recorder
import glasshouse/replay
import glasshouse/secret
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string

fn read_request(path) {
  v.Record(
    dict.from_list([
      #("path", v.String(path)),
      #("offset", v.Integer(0)),
      #("limit", v.Integer(1_000_000)),
    ]),
  )
}

fn recording() {
  let contents = v.Binary(<<"a file that is long enough to be stored":utf8>>)
  recorder.new(sha256)
  |> recorder.with_threshold(16)
  |> recorder.record(
    "ReadFile",
    read_request("notes.txt"),
    v.ok(contents),
    journal.Performed,
    Some("/home/notes.txt"),
    0,
    1,
  )
  |> recorder.record(
    "Now",
    v.unit(),
    v.Integer(1_700_000_000_000),
    journal.Performed,
    None,
    1,
    0,
  )
}

pub fn recorded_files_are_stored_once_test() {
  let recorder = recording()
  let assert [read, _] = recorder.journal(recorder)
  assert list.length(dict.to_list(recorder.store(recorder))) == 1
  assert journal.references([read]) != []
}

pub fn replay_answers_matching_effects_test() {
  let recorder = recording()
  let replay =
    replay.start(recorder.journal(recorder), recorder.store(recorder), [])
  let assert Ok(#(reply, _, replay)) =
    replay.next(replay, "ReadFile", read_request("notes.txt"), Nil)
  assert reply
    == v.ok(v.Binary(<<"a file that is long enough to be stored":utf8>>))
  let assert Ok(#(now, _, replay)) = replay.next(replay, "Now", v.unit(), Nil)
  assert now == v.Integer(1_700_000_000_000)
  assert replay.finish(replay) == Ok(Nil)
  assert replay.position(replay) == 2
}

pub fn replay_detects_a_different_request_test() {
  let recorder = recording()
  let replay =
    replay.start(recorder.journal(recorder), recorder.store(recorder), [])
  let assert Error(
    replay.Mismatch(position: 0, label: "ReadFile", ..) as divergence,
  ) = replay.next(replay, "ReadFile", read_request("other.txt"), Nil)
  let message = replay.describe(divergence, recorder.store(recorder))
  assert string.contains(message, "other.txt")
  assert string.contains(message, "notes.txt")
}

pub fn replay_detects_a_different_effect_test() {
  let recorder = recording()
  let replay =
    replay.start(recorder.journal(recorder), recorder.store(recorder), [])
  let assert Error(replay.Mismatch(..)) =
    replay.next(replay, "Now", v.unit(), Nil)
}

pub fn replay_detects_unrecorded_effects_test() {
  let replay = replay.start([], recorder.store(recording()), [])
  let assert Error(replay.Unrecorded(0, "Now", _)) =
    replay.next(replay, "Now", v.unit(), Nil)
}

pub fn replay_detects_unperformed_effects_test() {
  let recorder = recording()
  let replay =
    replay.start(recorder.journal(recorder), recorder.store(recorder), [])
  let assert Error(replay.Unperformed(0, journal.Entry(label: "ReadFile", ..))) =
    replay.finish(replay)
}

pub fn replay_without_the_store_is_unreadable_test() {
  let recorder = recording()
  let replay = replay.start(recorder.journal(recorder), dict.new(), [])
  let assert Error(_) =
    replay.next(replay, "ReadFile", read_request("notes.txt"), Nil)
}

fn authorized(token) {
  v.Record(dict.from_list([#("authorization", v.String("Bearer " <> token))]))
}

fn secret_session() {
  recorder.new(sha256)
  |> recorder.record(
    "MountSecret",
    v.String("/user/agent/github"),
    v.ok(v.String("ghp_real")),
    journal.Performed,
    None,
    0,
    0,
  )
  |> recorder.record(
    "Fetch",
    authorized("ghp_real"),
    v.ok(v.String("welcome ghp_real")),
    journal.Performed,
    None,
    0,
    0,
  )
}

pub fn mounted_secrets_are_never_recorded_test() {
  let recorder = secret_session()
  let recorded =
    recorder.journal(recorder)
    |> list.map(fn(entry) { string.inspect(entry) })
    |> string.join("")
  assert !string.contains(recorded, "ghp_real")
  assert string.contains(recorded, "⟦secret:/user/agent/github⟧")
}

pub fn replay_with_dummy_secret_matches_test() {
  let recorder = secret_session()
  let dummy = secret.dummy("/user/agent/github")
  let replay =
    replay.start(recorder.journal(recorder), recorder.store(recorder), [dummy])
  let assert Ok(#(mounted, _, replay)) =
    replay.next(replay, "MountSecret", v.String("/user/agent/github"), Nil)
  assert mounted == v.ok(v.String(dummy.value))
  let assert Ok(#(reply, _, replay)) =
    replay.next(replay, "Fetch", authorized(dummy.value), Nil)
  assert reply == v.ok(v.String("welcome " <> dummy.value))
  assert replay.finish(replay) == Ok(Nil)
}

pub fn fingerprint_identifies_without_storing_test() {
  let recorder = recorder.new(sha256)
  let a = recorder.fingerprint(recorder, v.String("Bearer token"))
  let b = recorder.fingerprint(recorder, v.String("Bearer token"))
  assert a == b
  assert recorder.store(recorder) == dict.new()
}

pub fn credential_variables_are_not_recorded_test() {
  let recorder =
    recorder.new(sha256)
    |> recorder.record(
      "Env",
      v.String("GITHUB_TOKEN"),
      v.some(v.String("ghp_env")),
      journal.Performed,
      None,
      0,
      0,
    )
    |> recorder.record(
      "Env",
      v.String("HOME"),
      v.some(v.String("/home/pea")),
      journal.Performed,
      None,
      0,
      0,
    )
  let recorded =
    recorder.journal(recorder)
    |> list.map(string.inspect)
    |> string.join("")
  assert !string.contains(recorded, "ghp_env")
  assert string.contains(recorded, "/home/pea")
}
