import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import overlay/eval/agent.{Reply}
import overlay/eval/environment
import overlay/eval/fixture/hub
import overlay/eval/model
import overlay/eval/module
import overlay/eval/report
import overlay/eval/run
import overlay/eval/session
import overlay/eval/suite
import overlay/eval/summary
import overlay/eval/trial

fn setup() {
  let assert Ok(hub) =
    hub.publish_directory(hub.new(), "test/fixtures/packages")
  let assert Ok(suite) = suite.load("test/fixtures/suites/example.eyg", hub)
  let assert Ok(loaded) =
    module.load("test/fixtures/packages/greeting/index.eyg")
  #(environment.Environment(..environment.empty(), hub:), suite, loaded)
}

/// Every task passed by the oracle, and failed by the null agent.
fn runs() {
  let #(environment, suite, loaded) = setup()
  let judge = model.Scripted(fn(_) { Reply("VERDICT: PASS", []) })
  let oracle =
    run.Config(
      ..run.config(
        suite,
        environment,
        session.Module(loaded),
        "greeting",
        model.Scripted(agent.null()),
        Some(judge),
        2,
      ),
      model_for: fn(task, _) { trial.oracle(task) },
    )
  let null =
    run.config(
      suite,
      environment,
      session.Module(loaded),
      "greeting",
      model.Scripted(agent.null()),
      None,
      2,
    )
  use oracle <- promise.await(run.run(oracle, fn(_) { Nil }))
  use null <- promise.map(run.run(null, fn(_) { Nil }))
  #(oracle, null)
}

pub fn runs_have_every_trial_in_order_test() {
  use #(oracle, _null) <- promise.map(runs())
  assert [
      #("add", 1),
      #("add", 2),
      #("fact", 1),
      #("fact", 2),
      #("greet", 1),
      #("greet", 2),
      #("note", 1),
      #("note", 2),
      #("project", 1),
      #("project", 2),
      #("quiet", 1),
      #("quiet", 2),
    ]
    == list.map(oracle.trials, fn(trial) { #(trial.task, trial.number) })
}

pub fn summaries_estimate_pass_rates_by_task_test() {
  use #(oracle, null) <- promise.map(runs())
  let passed = summary.summarise(oracle)
  assert 1.0 == passed.rate.mean
  assert 0.0 == passed.rate.standard_error
  assert 6 == passed.rate.samples
  let assert [add, ..] = passed.tasks
  assert 2 == add.passes
  assert 1.0 == add.pass_power_k
  assert [] == passed.failures

  let failed = summary.summarise(null)
  assert 0.0 == failed.rate.mean
  let assert [
    #("arithmetic", _),
    #("libraries", _),
    #("notes", _),
    #("workspace", _),
  ] = failed.tags
  // Checks that failed in both trials are counted twice.
  let assert [summary.Failure(count: 2, ..), ..] = failed.failures

  let comparison = summary.compare(passed, failed)
  assert 1.0 == comparison.difference.mean
  assert ["add", "fact", "greet", "note", "project", "quiet"]
    == comparison.improved
  assert [] == comparison.regressed
}

pub fn logs_are_read_back_for_comparison_test() {
  use #(oracle, null) <- promise.map(runs())
  let read = fn(run) {
    let assert Ok(decoded) =
      report.log(run)
      |> json.to_string
      |> json.parse(report.log_decoder())
    decoded
  }
  let #(header, decoded) = read(oracle)
  assert report.header(oracle) == header
  assert summary.summarise(oracle).tasks == decoded.tasks
  assert summary.summarise(oracle).rate == decoded.rate

  let comparison = report.comparison(read(oracle), read(null))
  assert string.contains(comparison, "A minus B is **+100pp**")
  assert string.contains(comparison, "| add | 100% | 0% | +100pp |")
}

pub fn markdown_reports_rates_and_failures_test() {
  use #(_oracle, null) <- promise.map(runs())
  let text = report.markdown(report.header(null), summary.summarise(null))
  assert string.contains(text, "Pass rate **0%**")
  assert string.contains(text, "| add | arithmetic | 0/2 | 0% | 0% |")
  assert string.contains(text, "## Failing checks")
  assert string.contains(text, "never said \"5\"")
}
