import eyg/interpreter/value as v
import glasshouse/journal
import glasshouse/value
import gleam/json
import gleam/option.{None, Some}

fn entry(answer) {
  journal.Entry(
    label: "ReadFile",
    lift: value.encode(v.String("a.txt")),
    reply: value.encode(v.ok(v.Binary(<<"hi">>))),
    answer:,
    path: Some("/tmp/a.txt"),
    started: 1_700_000_000_000,
    duration: 3,
  )
}

fn round_trip(entry) {
  journal.encode(entry)
  |> json.to_string
  |> json.parse(journal.decoder())
}

pub fn entry_round_trips_test() {
  let entry = entry(journal.Performed)
  assert round_trip(entry) == Ok(entry)
}

pub fn every_answer_round_trips_test() {
  [
    journal.Performed,
    journal.Gated,
    journal.Altered("bafyreia"),
    journal.Mocked,
    journal.Cached,
    journal.Simulated,
  ]
  |> list_each(fn(answer) {
    let entry = entry(answer)
    assert round_trip(entry) == Ok(entry)
  })
}

pub fn path_is_optional_test() {
  let entry = journal.Entry(..entry(journal.Performed), path: None)
  assert round_trip(entry) == Ok(entry)
}

pub fn write_effects_test() {
  assert journal.is_write("WriteFile")
  assert journal.is_write("Commit")
  assert !journal.is_write("ReadFile")
}

fn list_each(items, f) {
  case items {
    [] -> Nil
    [item, ..rest] -> {
      f(item)
      list_each(rest, f)
    }
  }
}
