import glasshouse/cohort
import glasshouse/fixtures
import glasshouse/run
import glasshouse/session
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub fn summary_test() {
  let #(session, store) = fixtures.session()
  let summary = cohort.summarize("baseline", session, store)
  assert summary.generations == 2
  assert summary.recorded == 0
  assert summary.live == session.Usage(300, 40)
  assert summary.tool_calls == 1
  assert summary.effects == 4
  assert summary.changes == [cohort.Change("/project/notes.txt", 2, 1)]
  assert summary.answer == "I numbered the line."
}

pub fn summary_round_trips_test() {
  let #(session, store) = fixtures.session()
  let summary =
    cohort.Summary(
      ..cohort.summarize("baseline", session, store),
      stopped: Some("diverged"),
    )
  assert json.parse(json.to_string(cohort.encode(summary)), cohort.decoder())
    == Ok(summary)
  let report = cohort.report_encode("session-1", [summary])
  assert json.parse(json.to_string(report), cohort.report_decoder())
    == Ok(#("session-1", [summary]))
}

pub fn table_test() {
  let #(session, store) = fixtures.session()
  let table = cohort.table([cohort.summarize("baseline", session, store)], "/")
  let assert [header, row] = string.split(table, "\n")
  assert string.starts_with(header, "variant")
  assert string.contains(row, " project/notes.txt +2 -1 ")
  assert string.contains(row, "340")
}

pub fn stopped_variants_test() {
  let #(session, _store) = fixtures.session()
  assert cohort.stopped(session) == None
  let events =
    list.map(session.events, fn(event) {
      case event {
        session.Execution(run: run.Run(kind: run.Tool(..), ..) as tool) ->
          session.Execution(
            run.Run(
              ..tool,
              outcome: run.Failed(cohort.unreproducible("a new fetch")),
            ),
          )
        _ -> event
      }
    })
  assert cohort.stopped(session.Session(..session, events:))
    == Some("a new fetch")
}
