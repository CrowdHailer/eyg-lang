import glasshouse/archive as portable
import glasshouse/cohort
import glasshouse/session
import glasshouse/timeline
import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import simplifile
import website/routes/glasshouse/debugger/state
import website/routes/glasshouse/debugger/view

fn archive(demo: state.Demo) {
  let assert Ok(text) =
    simplifile.read(
      "src/website/routes/glasshouse/demo/" <> demo.slug <> ".json",
    )
  text
}

// Every demo loaded, delivered in reverse to show the order does not matter.
fn loaded(query) {
  let #(model, _) = state.init(query)
  list.reverse(state.demos)
  |> list.fold(model, fn(model, demo) {
    send(model, state.ArchiveFetched(demo, Ok(archive(demo))))
  })
}

fn send(model, message) {
  let #(model, _) = state.update(model, message)
  model
}

fn effect_moment(model, label) {
  let assert Ok(trace) = state.active(model)
  let assert Ok(#(index, _)) =
    list.index_map(trace.moments, fn(m, i) { #(i, m) })
    |> list.find(fn(entry) {
      case entry.1 {
        state.Effect(frame) -> frame.entry.label == label
        _ -> False
      }
    })
  index
}

pub fn every_demo_is_fetched_test() {
  let #(model, actions) = state.init("")
  assert actions == list.map(state.demos, state.FetchArchive)
  assert model.loading == state.demos
}

pub fn sealed_cohort_loads_in_order_and_replays_test() {
  let #(model, actions) = state.init("demo=sandbox")
  assert actions == list.map(state.sandbox_demos, state.FetchArchive)
  let model =
    list.reverse(state.sandbox_demos)
    |> list.fold(model, fn(model, demo) {
      send(model, state.ArchiveFetched(demo, Ok(archive(demo))))
    })
  assert list.map(model.traces, fn(trace) { trace.name })
    == list.map(state.sandbox_demos, fn(demo) { demo.name })
  assert list.all(model.traces, fn(trace) {
    portable.missing(trace.archive) == []
  })
  let model = send(model, state.UserClickedReplay)
  let assert Ok(trace) = state.active(model)
  let assert Some(reports) = trace.replay
  assert list.all(reports, fn(report) { report.problem == None })
  let assert Ok(stopped) = list.last(model.traces)
  let assert Some(reason) = cohort.stopped(stopped.archive.session)
  assert string.contains(reason, "not permitted")
}

pub fn traces_keep_the_demo_order_test() {
  let model = loaded("")
  assert list.map(model.traces, fn(t) { t.slug })
    == list.map(state.demos, fn(d) { d.slug })
  assert model.loading == []
  let assert Ok(trace) = state.active(model)
  assert trace.name == "Recorded session"
}

pub fn every_event_is_a_moment_test() {
  let model = loaded("")
  let assert Ok(trace) = state.active(model)
  let session = trace.archive.session
  let effects =
    list.fold(session.runs(session), 0, fn(total, run) {
      total + list.length(run.journal)
    })
  let others =
    list.count(session.events, fn(event) {
      case event {
        session.Execution(..) -> False
        _ -> True
      }
    })
  assert list.length(trace.moments) == effects + others
}

pub fn moving_through_the_session_test() {
  let model = loaded("")
  assert model.moment == 0
  let model = send(model, state.UserPressedKey("ArrowRight"))
  assert model.moment == 1
  let model = send(model, state.UserPressedKey("ArrowLeft"))
  let model = send(model, state.UserPressedKey("ArrowLeft"))
  assert model.moment == 0
  let model = send(model, state.UserMovedScrubber("1000"))
  let assert Ok(trace) = state.active(model)
  assert model.moment == list.length(trace.moments) - 1
}

pub fn files_are_known_at_each_moment_test() {
  let model = loaded("")
  let assert Ok(trace) = state.active(model)
  let report = trace.archive.session.cwd <> "/reports/signups.md"
  let write = effect_moment(model, "WriteFile")
  let before = send(model, state.UserSelectedMoment(write - 1))
  assert dict.get(state.files(before), report) == Error(Nil)
  let after = send(model, state.UserSelectedMoment(write))
  let assert Ok(timeline.File(timeline.Whole(bytes))) =
    dict.get(state.files(after), report)
  let assert Ok(text) = bit_array.to_string(bytes)
  assert string.contains(text, "| blog | 3 |")
  assert state.changed(after) == Some(report)
  assert list.contains(state.written(after), report)
}

pub fn the_demo_replays_in_the_browser_test() {
  let model = loaded("") |> send(state.UserClickedReplay)
  assert model.panel == state.Replay
  let assert Ok(state.Trace(replay: Some(reports), ..)) = state.active(model)
  let assert [_, ..] = reports
  assert list.all(reports, fn(report) { report.problem == None })
}

pub fn variants_are_compared_test() {
  let summaries = state.cohort(loaded(""))
  let assert [recorded, same, totals, blog, website] = summaries
  assert recorded.recorded == 0
  assert same.recorded == same.generations
  assert same.live.input + same.live.output == 0
  assert totals.effects > recorded.effects
  assert blog.tool_calls == 1
  let assert Some(reason) = website.stopped
  assert string.contains(reason, "newsletter.example.com")
}

pub fn selecting_a_trace_keeps_the_moment_test() {
  let model =
    loaded("")
    |> send(state.UserSelectedMoment(5))
    |> send(state.UserSelectedTrace(2))
  let assert Ok(trace) = state.active(model)
  assert trace.slug == "with-totals"
  assert model.moment == 5
  assert state.active_index(model) == 2
}

pub fn links_open_a_trace_at_a_moment_test() {
  let model = loaded("trace=with-totals&step=7")
  let assert Ok(trace) = state.active(model)
  assert trace.slug == "with-totals"
  assert model.moment == 7
}

pub fn uploads_are_opened_test() {
  let assert [first, ..] = state.demos
  let model =
    loaded("")
    |> send(state.ArchiveUploaded("mine.json", Ok(archive(first))))
  let assert Ok(trace) = state.active(model)
  assert trace.name == "mine.json"
  assert list.length(model.traces) == list.length(state.demos) + 1
  let model = send(model, state.ArchiveUploaded("broken.json", Ok("{}")))
  assert model.error
    == Some("broken.json: the file is not a glasshouse archive")
}

pub fn downloads_the_active_trace_test() {
  let #(_, actions) = state.update(loaded(""), state.UserClickedDownload)
  let assert [state.DownloadArchive(name:, ..)] = actions
  assert string.ends_with(name, ".json")
}

pub fn every_panel_renders_test() {
  let model = loaded("")
  let write = effect_moment(model, "WriteFile")
  let html =
    model
    |> send(state.UserSelectedMoment(write))
    |> view.view
    |> element.to_string
  assert string.contains(html, "WriteFile")
  assert string.contains(html, "+ | blog | 3 |")
  let html =
    model
    |> send(state.UserOpenedPanel(state.Compare))
    |> view.view
    |> element.to_string
  assert string.contains(html, "check the website")
  let html = view.view(state.init("").0) |> element.to_string
  assert string.contains(html, "Loading the demo session")
}

pub fn highlight_test() {
  let html =
    view.highlight("let x = perform Fetch(!int_add(1, 2)) // done\n\"text\"")
    |> list.map(element.to_string)
    |> string.concat
  assert string.contains(html, "<span class=\"gh-c-keyword\">let</span>")
  assert string.contains(html, "<span class=\"gh-c-tag\">Fetch</span>")
  assert string.contains(html, "<span class=\"gh-c-builtin\">!int_add</span>")
  assert string.contains(html, "<span class=\"gh-c-comment\">// done</span>")
  assert string.contains(
    html,
    "<span class=\"gh-c-string\">&quot;text&quot;</span>",
  )
}
