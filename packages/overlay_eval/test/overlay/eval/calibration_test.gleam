import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import overlay/eval/agent.{Reply}
import overlay/eval/calibration.{Agreement, Label}
import overlay/eval/environment
import overlay/eval/fixture/hub
import overlay/eval/model
import overlay/eval/module
import overlay/eval/report.{Judged}
import overlay/eval/run
import overlay/eval/session
import overlay/eval/suite

/// The example suite has one judged check, on the `greet` task.
fn judged_log(judge) {
  let assert Ok(hub) =
    hub.publish_directory(hub.new(), "test/fixtures/packages")
  let assert Ok(suite) = suite.load("test/fixtures/suites/example.eyg", hub)
  let suite = suite.tagged(suite, ["libraries"])
  let assert Ok(loaded) =
    module.load("test/fixtures/packages/greeting/index.eyg")
  let config =
    run.config(
      suite,
      environment.Environment(..environment.empty(), hub:),
      session.Module(loaded),
      "greeting",
      model.Scripted(agent.null()),
      Some(model.Scripted(fn(_) { Reply(judge, []) })),
      2,
    )
  use run <- promise.map(run.run(config, fn(_) { Nil }))
  let assert Ok(judged) =
    report.log(run)
    |> json.to_string
    |> json.parse(report.judged_decoder())
  judged
}

pub fn judged_checks_are_read_back_from_a_log_test() {
  use judged <- promise.map(judged_log("VERDICT: PASS"))
  assert [
      Judged("greet", 1, "The reply greets Ada by name", "pass"),
      Judged("greet", 2, "The reply greets Ada by name", "pass"),
    ]
    == judged
}

/// A judge with nothing to say cannot be calibrated, and must not look like a
/// judge that decided.
pub fn an_undecided_judge_is_unknown_test() {
  use judged <- promise.map(judged_log("I would rather not."))
  let assert [Judged(verdict: "unknown", ..), _] = judged
  let labels = [
    Label("greet", 1, "The reply greets Ada by name", True),
    Label("greet", 2, "The reply greets Ada by name", False),
  ]
  let assert [Agreement(unknown: 2, ..) as agreement] =
    calibration.compare(judged, labels)
  assert 0 == calibration.decided(agreement)
  assert 0.0 == calibration.kappa(agreement)
}

fn judged(verdicts) {
  list.index_map(verdicts, fn(verdict, index) {
    Judged("task", index + 1, "answers the question", verdict)
  })
}

fn labelled(verdicts) {
  list.index_map(verdicts, fn(passed, index) {
    Label("task", index + 1, "answers the question", passed)
  })
}

pub fn agreement_keeps_passes_and_fails_apart_test() {
  //             the judge: pass  pass  pass  fail
  //                   you: pass  fail  pass  fail
  let judged = judged(["pass", "pass", "pass", "fail"])
  let labels = labelled([True, False, True, False])
  let assert [agreement] = calibration.compare(judged, labels)
  assert Agreement(
      criterion: "answers the question",
      agreed_pass: 2,
      agreed_fail: 1,
      judge_passed_you_failed: 1,
      judge_failed_you_passed: 0,
      unknown: 0,
      missing: 0,
    )
    == agreement
  assert 4 == calibration.decided(agreement)
  // Every trial you passed, the judge passed.
  assert 1.0 == calibration.recall(agreement)
  // Of the two you failed, it failed one.
  assert 0.5 == calibration.specificity(agreement)
}

/// The number that flatters a judge: a judge that passes everything agrees
/// with a labeller who passed nine of ten, and has learnt nothing.
pub fn kappa_discounts_agreement_by_chance_test() {
  let generous =
    judged([
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
    ])
  let labels =
    labelled([True, True, True, True, True, True, True, True, True, False])
  let assert [agreement] = calibration.compare(generous, labels)
  assert 0.0 == calibration.kappa(agreement)
  assert 1.0 == calibration.recall(agreement)
  assert 0.0 == calibration.specificity(agreement)

  let careful =
    judged([
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "pass",
      "fail",
    ])
  let assert [agreement] = calibration.compare(careful, labels)
  assert 1.0 == calibration.kappa(agreement)
  assert 1.0 == calibration.specificity(agreement)
}

pub fn a_label_with_no_judged_check_is_not_agreement_test() {
  let assert [agreement] =
    calibration.compare(judged(["pass"]), labelled([True, True]))
  assert 1 == agreement.missing
  assert 1 == calibration.decided(agreement)
}

pub fn labels_are_pass_or_fail_test() {
  let parse = fn(text) { json.parse(text, calibration.labels_decoder()) }
  assert Ok([Label("greet", 2, "is polite", True)])
    == parse(
      "[{\"task\": \"greet\", \"trial\": 2, \"criterion\": \"is polite\", \"verdict\": \"pass\"}]",
    )
  // An unlabelled check is a mistake, not a fail.
  let assert Error(_) =
    parse(
      "[{\"task\": \"greet\", \"trial\": 2, \"criterion\": \"is polite\", \"verdict\": \"\"}]",
    )
}

pub fn criteria_are_reported_separately_and_together_test() {
  let judged = [
    Judged("greet", 1, "is polite", "pass"),
    Judged("greet", 1, "names the file", "fail"),
  ]
  let labels = [
    Label("greet", 1, "is polite", True),
    Label("greet", 1, "names the file", True),
  ]
  let assert [polite, file, every] = calibration.compare(judged, labels)
  assert "is polite" == polite.criterion
  assert "names the file" == file.criterion
  assert "every criterion" == every.criterion
  assert 2 == calibration.decided(every)
  assert 0.5 == calibration.recall(every)

  let text = calibration.markdown([polite, file, every])
  assert string.contains(text, "| is polite | 1 | 100% | 0% |")
  assert string.contains(text, "| every criterion | 2 | 50% | 0% |")
  // Two labels are not a calibration, and the report says so.
  assert string.contains(text, "Fewer than twenty trials decided a criterion")
}
