//// Compare a judge with your own labels.
////
//// A judge is a measuring instrument. Before trusting one, grade some trials
//// yourself and compare. Agreement alone flatters a judge on an unbalanced
//// set, so the counts are kept apart: of the trials you passed, how many did
//// the judge pass, and of the ones you failed, how many did it fail.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import overlay/eval/report.{type Judged}
import overlay/eval/stats

/// A verdict of your own for one judged check of one trial.
pub type Label {
  Label(task: String, trial: Int, criterion: String, passed: Bool)
}

/// Labels are a list of `{task, trial, criterion, verdict}`, the verdict
/// "pass" or "fail".
pub fn labels_decoder() -> decode.Decoder(List(Label)) {
  decode.list({
    use task <- decode.field("task", decode.string)
    use trial <- decode.field("trial", decode.int)
    use criterion <- decode.field("criterion", decode.string)
    use verdict <- decode.field("verdict", decode.string)
    case verdict {
      "pass" -> decode.success(Label(task:, trial:, criterion:, passed: True))
      "fail" -> decode.success(Label(task:, trial:, criterion:, passed: False))
      // An unlabelled check must not be counted as a fail.
      _ ->
        decode.failure(
          Label(task:, trial:, criterion:, passed: False),
          "a verdict of pass or fail",
        )
    }
  })
}

pub type Agreement {
  Agreement(
    criterion: String,
    // The judge passed a trial you passed, and so on.
    agreed_pass: Int,
    agreed_fail: Int,
    judge_passed_you_failed: Int,
    judge_failed_you_passed: Int,
    // The judge could not tell, or a label has no judged check.
    unknown: Int,
    missing: Int,
  )
}

/// Compare judged checks with labels, by criterion, and over everything.
pub fn compare(judged: List(Judged), labels: List(Label)) -> List(Agreement) {
  let criteria =
    list.map(labels, fn(label) { label.criterion })
    |> list.unique
    |> list.sort(string.compare)
  let by_criterion =
    list.map(criteria, fn(criterion) {
      agreement(
        criterion,
        list.filter(labels, fn(label) { label.criterion == criterion }),
        judged,
      )
    })
  case by_criterion {
    [] | [_] -> by_criterion
    _ ->
      list.append(by_criterion, [agreement("every criterion", labels, judged)])
  }
}

fn agreement(criterion, labels: List(Label), judged: List(Judged)) {
  list.fold(labels, Agreement(criterion, 0, 0, 0, 0, 0, 0), fn(counts, label) {
    let verdict =
      list.find_map(judged, fn(judged: Judged) {
        case
          judged.task == label.task
          && judged.trial == label.trial
          && judged.criterion == label.criterion
        {
          True -> Ok(judged.verdict)
          False -> Error(Nil)
        }
      })
    case verdict, label.passed {
      Ok("pass"), True ->
        Agreement(..counts, agreed_pass: counts.agreed_pass + 1)
      Ok("fail"), False ->
        Agreement(..counts, agreed_fail: counts.agreed_fail + 1)
      Ok("pass"), False ->
        Agreement(
          ..counts,
          judge_passed_you_failed: counts.judge_passed_you_failed + 1,
        )
      Ok("fail"), True ->
        Agreement(
          ..counts,
          judge_failed_you_passed: counts.judge_failed_you_passed + 1,
        )
      Ok(_), _ -> Agreement(..counts, unknown: counts.unknown + 1)
      Error(Nil), _ -> Agreement(..counts, missing: counts.missing + 1)
    }
  })
}

/// The trials both you and the judge decided.
pub fn decided(agreement: Agreement) -> Int {
  agreement.agreed_pass
  + agreement.agreed_fail
  + agreement.judge_passed_you_failed
  + agreement.judge_failed_you_passed
}

/// Of the trials you passed, the share the judge passed.
pub fn recall(agreement: Agreement) -> Float {
  share(
    agreement.agreed_pass,
    agreement.agreed_pass + agreement.judge_failed_you_passed,
  )
}

/// Of the trials you failed, the share the judge failed.
pub fn specificity(agreement: Agreement) -> Float {
  share(
    agreement.agreed_fail,
    agreement.agreed_fail + agreement.judge_passed_you_failed,
  )
}

/// Agreement beyond what agreeing by chance would give, Cohen's kappa.
pub fn kappa(agreement: Agreement) -> Float {
  let total = int.to_float(decided(agreement))
  case total >. 0.0 {
    False -> 0.0
    True -> {
      let observed =
        int.to_float(agreement.agreed_pass + agreement.agreed_fail) /. total
      let judge_pass =
        int.to_float(agreement.agreed_pass + agreement.judge_passed_you_failed)
        /. total
      let label_pass =
        int.to_float(agreement.agreed_pass + agreement.judge_failed_you_passed)
        /. total
      let chance =
        judge_pass
        *. label_pass
        +. { 1.0 -. judge_pass }
        *. { 1.0 -. label_pass }
      case chance <. 1.0 {
        True -> { observed -. chance } /. { 1.0 -. chance }
        False -> 1.0
      }
    }
  }
}

/// Criteria are sentences, and a table is not the place to read them whole.
fn short(criterion) {
  case string.length(criterion) > 70 {
    True -> string.slice(criterion, 0, 69) <> "…"
    False -> criterion
  }
}

fn share(part, whole) {
  case whole {
    0 -> 0.0
    _ -> int.to_float(part) /. int.to_float(whole)
  }
}

/// A calibration report in markdown.
pub fn markdown(agreements: List(Agreement)) -> String {
  let rows =
    list.map(agreements, fn(agreement) {
      "| "
      <> short(agreement.criterion)
      <> " | "
      <> int.to_string(decided(agreement))
      <> " | "
      <> stats.percent(recall(agreement))
      <> " | "
      <> stats.percent(specificity(agreement))
      <> " | "
      <> float.to_string(float.to_precision(kappa(agreement), 2))
      <> " | "
      <> int.to_string(agreement.unknown)
      <> " | "
      <> int.to_string(agreement.missing)
      <> " |"
    })
  "# Judge calibration

Of the trials you passed, the share the judge passed, and of the trials you
failed, the share it failed. Kappa is agreement beyond chance.

| Criterion | Decided | You passed | You failed | Kappa | Unknown | Not judged |
| --- | --- | --- | --- | --- | --- | --- |
" <> string.join(rows, "\n") <> "
" <> caution(agreements)
}

/// Thirty trials is the usual advice, and a judge measured on five has not
/// been measured.
fn caution(agreements) {
  case list.any(agreements, fn(agreement) { decided(agreement) < 20 }) {
    False -> ""
    True ->
      "\nFewer than twenty trials decided a criterion here, which shows where"
      <> " to look rather than how well the judge does. Grade more.\n"
  }
}
