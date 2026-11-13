import glasshouse/archive
import glasshouse/fixtures
import glasshouse/helpers.{sha256}
import glasshouse/lock
import glasshouse/run
import glasshouse/session
import glasshouse/store
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string

pub fn lock_round_trips_test() {
  let lock =
    lock.empty()
    |> lock.add_file(
      "/p/helper.eyg",
      lock.File(source: "bafys", module: "bafym"),
    )
    |> lock.add_package("standard", lock.Release(version: 3, module: "bafystd"))
    |> lock.add_version("json", 1, "bafyjson")
  assert json.parse(json.to_string(lock.encode(lock)), lock.decoder())
    == Ok(lock)
  assert list.sort(lock.references(lock), string.compare)
    == ["bafyjson", "bafym", "bafys", "bafystd"]
}

pub fn every_run_kind_round_trips_test() {
  let #(session, _) = fixtures.session()
  let assert [first, ..] = session.runs(session)
  [
    run.Block,
    run.Script(["a", "b"]),
    run.Config,
    run.Tool("call"),
    run.Cell,
  ]
  |> list.each(fn(kind) {
    let r = run.Run(..first, kind:)
    assert json.parse(json.to_string(run.encode(r)), run.decoder()) == Ok(r)
  })
}

pub fn every_outcome_round_trips_test() {
  let #(session, _) = fixtures.session()
  let assert [first, ..] = session.runs(session)
  [run.Finished, run.Exited(3), run.Failed("boom"), run.Rejected("type error")]
  |> list.each(fn(outcome) {
    let r = run.Run(..first, outcome:, program: None, origin: run.Repl)
    assert json.parse(json.to_string(run.encode(r)), run.decoder()) == Ok(r)
  })
}

pub fn session_round_trips_test() {
  let #(session, _) = fixtures.session()
  assert json.parse(json.to_string(session.encode(session)), session.decoder())
    == Ok(session)
}

pub fn usage_sums_generations_test() {
  let #(session, _) = fixtures.session()
  assert session.usage(session)
    == #(session.Usage(300, 40), session.Usage(0, 0))
}

pub fn archive_round_trips_test() {
  let #(session, store) = fixtures.session()
  let archive =
    archive.new(session, store)
    |> archive.add_link(archive.Langfuse("http://localhost:3000", "abc"))
  let assert Ok(decoded) = archive.from_string(archive.to_string(archive))
  assert decoded == archive
  assert archive.missing(decoded) == []
  assert store.corrupt(decoded.store, sha256) == []
}

pub fn archive_prunes_unreferenced_blocks_test() {
  let #(session, store) = fixtures.session()
  let #(store, unused) = store.put_binary(store, <<"unused">>, sha256)
  let archive = archive.new(session, store)
  assert !dict.has_key(archive.store, unused)
}

pub fn archive_reports_missing_blocks_test() {
  let #(session, _) = fixtures.session()
  let archive = archive.new(session, store.new())
  assert archive.missing(archive) != []
}

pub fn not_an_archive_test() {
  assert archive.from_string("{\"glasshouse\": 2}")
    == Error("the file is not a glasshouse archive")
  assert archive.from_string("nope") == Error("the archive is not JSON")
}
