//// The example contexts in eyg_packages, checked against the repository they
//// describe and run in sessions.

import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import gleam/string
import overlay/eval
import overlay/eval/agent.{Reply}
import overlay/eval/evaluate
import overlay/eval/fixture/hub
import overlay/eval/model
import overlay/eval/module
import overlay/eval/session
import overlay/eval/suite
import overlay/eval/transcript
import simplifile

const librarian = "../../eyg_packages/overlay_librarian/index.eyg"

const maintainer = "../../eyg_packages/overlay_maintainer/index.eyg"

pub fn context_tasks_have_working_references_and_reject_empty_agents_test() {
  let assert Ok(environment) = eval.environment("../..")
  let assert Ok(suite) = suite.load("suites/contexts.eyg", environment.hub)
  assert list.length(suite.tasks) == 16
  list.fold(suite.tasks, promise.resolve(Nil), fn(done, task) {
    use Nil <- promise.await(done)
    use checked <- promise.map(eval.validate_task(
      environment,
      session.NoContext,
      task,
    ))
    assert checked == []
    Nil
  })
}

fn setup(path) {
  let assert Ok(environment) = eval.environment("../..")
  let assert Ok(loaded) = module.load_pinned(path, hub.resolve(environment.hub))
  let assert Ok(value) = evaluate.module(loaded, environment.hub)
  #(environment, loaded, value)
}

fn field(value, path) {
  list.fold(path, value, fn(value, key) {
    let assert Ok(value) = cast.field(key, Ok, value)
    value
  })
}

fn strings(value, key) {
  let assert Ok(items) = cast.as_list(value)
  list.map(items, fn(item) {
    let assert Ok(text) = cast.field(key, cast.as_string, item)
    text
  })
}

pub fn every_library_in_the_catalogue_is_published_test() {
  let #(environment, _, context) = setup(librarian)
  let published = list.map(environment.hub.releases, fn(r) { "@" <> r.package })
  let references = strings(field(context, ["libraries", "all"]), "reference")
  assert [] == list.filter(references, fn(r) { !list.contains(published, r) })
}

pub fn every_guide_in_the_index_is_on_the_site_test() {
  let #(environment, _, context) = setup(librarian)
  let slugs = strings(field(context, ["guides", "all"]), "slug")
  let site = list.map(environment.site.guides, fn(guide) { guide.slug })
  assert [] == list.filter(slugs, fn(slug) { !list.contains(site, slug) })
  // New guides should be added to the index.
  assert [] == list.filter(site, fn(slug) { !list.contains(slugs, slug) })
}

pub fn every_mapped_source_path_exists_test() {
  let #(_, _, context) = setup(maintainer)
  let paths = strings(field(context, ["source", "map"]), "path")
  assert []
    == list.filter(paths, fn(path) {
      !result_true(simplifile.is_file("../../" <> path))
      && !result_true(simplifile.is_directory("../../" <> path))
    })
}

fn result_true(result) {
  result == Ok(True)
}

fn run(path, code, workspace) {
  let #(environment, loaded, _) = setup(path)
  let agent = agent.scripted([[Reply("", [code]), Reply("done", [])]])
  let config =
    session.Config(
      environment:,
      context: session.Module(loaded),
      model: model.Scripted(agent),
      workspace:,
      prompts: ["go"],
      max_model_calls: 4,
    )
  use transcript <- promise.map(session.run(config))
  let assert [run] = transcript.runs(transcript)
  #(run.outcome, transcript)
}

pub fn libraries_are_searched_in_a_session_test() {
  use #(outcome, _) <- promise.map(run(
    librarian,
    "context.libraries.search(\"parse json\")",
    option.None,
  ))
  let assert transcript.Computed(v.LinkedList([first, ..])) = outcome
  assert Ok("json") == cast.field("name", cast.as_string, first)
}

pub fn guides_are_read_from_the_site_in_a_session_test() {
  use #(outcome, _) <- promise.map(run(
    librarian,
    "context.guides.read(\"json\")",
    option.None,
  ))
  let assert transcript.Computed(v.Tagged("Ok", v.String(text))) = outcome
  assert string.contains(text, "@json")
}

pub fn source_is_read_from_the_repository_in_a_session_test() {
  use #(outcome, _) <- promise.map(run(
    maintainer,
    "context.source.read(\"packages/touch_grass/src/touch_grass/harness/browser.gleam\")",
    option.None,
  ))
  let assert transcript.Computed(v.Tagged("Ok", v.String(text))) = outcome
  assert string.contains(text, "Sleep")
}

pub fn directories_are_listed_from_the_repository_in_a_session_test() {
  use #(outcome, _) <- promise.map(run(
    maintainer,
    "context.source.list(\"eyg_packages\")",
    option.None,
  ))
  let assert transcript.Computed(v.Tagged("Ok", v.LinkedList(entries))) =
    outcome
  let paths =
    list.map(entries, fn(entry) {
      let assert Ok(path) = cast.field("path", cast.as_string, entry)
      path
    })
  assert list.contains(paths, "eyg_packages/overlay_maintainer")
}

pub fn notes_are_written_in_a_workspace_session_test() {
  use #(outcome, transcript) <- promise.map(run(
    maintainer,
    "context.workspace.write_note({name: \"Parsing JSON\", description: \"Use @json\", date: \"2026-09-17\", body: \"Decode fields.\"})",
    Some([]),
  ))
  assert transcript.Computed(v.Tagged("Ok", v.String("notes/parsing-json.md")))
    == outcome
  let assert Some(files) = transcript.workspace
  let assert Ok(_) = list.key_find(files, "notes/parsing-json.md")
  Nil
}

pub fn the_overlay_catalogue_example_runs_against_the_current_api_test() {
  let #(_, _, context) = setup(librarian)
  let assert Ok(entries) = cast.as_list(field(context, ["libraries", "all"]))
  let assert Ok(entry) =
    list.find(entries, fn(entry) {
      cast.field("name", cast.as_string, entry) == Ok("overlay")
    })
  let assert Ok(code) = cast.field("example", cast.as_string, entry)
  use #(outcome, _) <- promise.map(run(librarian, code, option.None))
  let assert transcript.Computed(v.Record(_)) = outcome
  Nil
}
