//// Reports of runs, for people and for later comparison.
////
//// A run is written as a JSON log, a markdown summary and a markdown file for
//// each trial. Logs are enough to compare runs without running them again.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import overlay/eval/grade
import overlay/eval/render
import overlay/eval/run.{type Run}
import overlay/eval/stats
import overlay/eval/summary.{type Summary, Summary}
import overlay/eval/task
import overlay/eval/trial.{type Trial}

pub const schema = "overlay-eval/1"

/// The details of a run a report needs, as written in a log.
pub type Header {
  Header(
    started: String,
    suite: String,
    context: String,
    model: String,
    judge: String,
    trials_per_task: Int,
  )
}

pub fn header(run: Run) -> Header {
  Header(
    started: run.started,
    suite: run.suite,
    context: run.context,
    model: run.model,
    judge: run.judge,
    trials_per_task: run.trials_per_task,
  )
}

/// The log of a run: its header, summary and every trial's checks.
pub fn log(run: Run) -> json.Json {
  let summary = summary.summarise(run)
  let Header(started:, suite:, context:, model:, judge:, trials_per_task:) =
    header(run)
  json.object([
    #("schema", json.string(schema)),
    #("started", json.string(started)),
    #("suite", json.string(suite)),
    #("context", json.string(context)),
    #("model", json.string(model)),
    #("judge", json.string(judge)),
    #("trials_per_task", json.int(trials_per_task)),
    #("pass_rate", estimate_encode(summary.rate)),
    #("score", estimate_encode(summary.score)),
    #(
      "tasks",
      json.array(summary.tasks, fn(task: summary.TaskResult) {
        json.object([
          #("name", json.string(task.name)),
          #("tags", json.array(task.tags, json.string)),
          #("trials", json.int(task.trials)),
          #("passes", json.int(task.passes)),
          #("rate", json.float(task.rate)),
          #("score", json.float(task.score)),
          #("pass_at_k", json.float(task.pass_at_k)),
          #("pass_power_k", json.float(task.pass_power_k)),
          #("model_calls", json.float(task.model_calls)),
          #("failed_runs", json.float(task.failed_runs)),
          #("milliseconds", json.float(task.milliseconds)),
        ])
      }),
    ),
    #(
      "failures",
      json.array(summary.failures, fn(failure: summary.Failure) {
        json.object([
          #("task", json.string(failure.task)),
          #("check", json.string(failure.check)),
          #("count", json.int(failure.count)),
          #("reason", json.string(failure.reason)),
        ])
      }),
    ),
    #("trials", json.array(run.trials, trial_encode)),
  ])
}

fn estimate_encode(estimate: stats.Estimate) {
  let #(low, high) = stats.interval(estimate)
  json.object([
    #("mean", json.float(estimate.mean)),
    #("standard_error", json.float(estimate.standard_error)),
    #("low", json.float(low)),
    #("high", json.float(high)),
    #("samples", json.int(estimate.samples)),
  ])
}

fn trial_encode(trial: Trial) {
  json.object([
    #("task", json.string(trial.task)),
    #("number", json.int(trial.number)),
    #("passed", json.bool(trial.passed)),
    #("score", json.float(trial.score)),
    #("milliseconds", json.int(trial.milliseconds)),
    #("model_calls", json.int(trial.transcript.model_calls)),
    #("stop", json.string(render.stop(trial.transcript.stop))),
    #(
      "checks",
      json.array(trial.graded, fn(graded) {
        let #(verdict, detail) = verdict_parts(graded.verdict)
        json.object([
          #("check", json.string(task.describe(graded.check))),
          #("verdict", json.string(verdict)),
          #("detail", json.string(detail)),
        ])
      }),
    ),
  ])
}

fn verdict_parts(verdict) {
  case verdict {
    grade.Pass(evidence) -> #("pass", evidence)
    grade.Fail(reason) -> #("fail", reason)
    grade.Unknown(reason) -> #("unknown", reason)
  }
}

/// Read the header and summary back from a log.
pub fn log_decoder() -> decode.Decoder(#(Header, Summary)) {
  use schema_version <- decode.field("schema", decode.string)
  use <- guard(schema_version == schema, "log schema " <> schema)
  use started <- decode.field("started", decode.string)
  use suite <- decode.field("suite", decode.string)
  use context <- decode.field("context", decode.string)
  use model <- decode.field("model", decode.string)
  use judge <- decode.field("judge", decode.string)
  use trials_per_task <- decode.field("trials_per_task", decode.int)
  use tasks <- decode.field(
    "tasks",
    decode.list({
      use name <- decode.field("name", decode.string)
      use tags <- decode.field("tags", decode.list(decode.string))
      use trials <- decode.field("trials", decode.int)
      use passes <- decode.field("passes", decode.int)
      use rate <- decode.field("rate", number())
      use score <- decode.field("score", number())
      use pass_at_k <- decode.field("pass_at_k", number())
      use pass_power_k <- decode.field("pass_power_k", number())
      use model_calls <- decode.field("model_calls", number())
      use failed_runs <- decode.field("failed_runs", number())
      use milliseconds <- decode.field("milliseconds", number())
      decode.success(summary.TaskResult(
        name:,
        tags:,
        trials:,
        passes:,
        rate:,
        score:,
        pass_at_k:,
        pass_power_k:,
        model_calls:,
        failed_runs:,
        milliseconds:,
      ))
    }),
  )
  use failures <- decode.field(
    "failures",
    decode.list({
      use task <- decode.field("task", decode.string)
      use check <- decode.field("check", decode.string)
      use count <- decode.field("count", decode.int)
      use reason <- decode.field("reason", decode.string)
      decode.success(summary.Failure(task:, check:, count:, reason:))
    }),
  )
  let header =
    Header(started:, suite:, context:, model:, judge:, trials_per_task:)
  let tags =
    list.flat_map(tasks, fn(task) { task.tags })
    |> list.unique
    |> list.map(fn(tag) {
      let rates =
        list.filter(tasks, fn(task) { list.contains(task.tags, tag) })
        |> list.map(fn(task) { task.rate })
      #(tag, stats.estimate(rates))
    })
  decode.success(#(
    header,
    Summary(
      tasks:,
      rate: stats.estimate(list.map(tasks, fn(task) { task.rate })),
      score: stats.estimate(list.map(tasks, fn(task) { task.score })),
      tags:,
      failures:,
    ),
  ))
}

fn guard(condition, expected, then) {
  case condition {
    True -> then()
    False -> decode.failure(#(Header("", "", "", "", "", 0), empty()), expected)
  }
}

fn empty() {
  Summary([], stats.estimate([]), stats.estimate([]), [], [])
}

// JSON writes whole floats as integers.
fn number() {
  decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])
}

/// A summary of a run in markdown.
pub fn markdown(header: Header, summary: Summary) -> String {
  let Header(started:, suite:, context:, model:, judge:, trials_per_task:) =
    header
  let k = int.to_string(trials_per_task)
  let #(low, high) = stats.interval(summary.rate)
  let tasks =
    list.map(summary.tasks, fn(task) {
      "| "
      <> task.name
      <> " | "
      <> string.join(task.tags, ", ")
      <> " | "
      <> int.to_string(task.passes)
      <> "/"
      <> int.to_string(task.trials)
      <> " | "
      <> stats.percent(task.pass_at_k)
      <> " | "
      <> stats.percent(task.pass_power_k)
      <> " | "
      <> stats.percent(task.score)
      <> " | "
      <> decimal(task.model_calls)
      <> " | "
      <> decimal(task.failed_runs)
      <> " |"
    })
  let tags =
    list.map(summary.tags, fn(tag) {
      let #(name, estimate) = tag
      let #(low, high) = stats.interval(estimate)
      "| "
      <> name
      <> " | "
      <> int.to_string(estimate.samples)
      <> " | "
      <> stats.percent(estimate.mean)
      <> " | "
      <> case estimate.samples < 2 {
        True -> "insufficient tasks"
        False -> range(low, high)
      }
      <> " |"
    })
  let failures =
    list.map(summary.failures, fn(failure) {
      "- **"
      <> failure.task
      <> "** "
      <> failure.check
      <> " ("
      <> int.to_string(failure.count)
      <> "×): "
      <> one_line(failure.reason)
    })
  [
    "# " <> suite,
    "Context `"
      <> context
      <> "`, model `"
      <> model
      <> "`, judge `"
      <> judge
      <> "`, "
      <> k
      <> " trials per task, started "
      <> started
      <> ".",
    "Pass rate **"
      <> stats.percent(summary.rate.mean)
      <> "** (95% CI "
      <> case summary.rate.samples < 2 {
      True -> "insufficient tasks"
      False -> range(low, high)
    }
      <> ") over "
      <> int.to_string(summary.rate.samples)
      <> " tasks, mean score "
      <> stats.percent(summary.score.mean)
      <> ".",
    "| Task | Tags | Passed | pass@"
      <> k
      <> " | pass^"
      <> k
      <> " | Score | Model calls | Failed runs |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n"
      <> string.join(tasks, "\n"),
    "## By tag\n\n| Tag | Tasks | Pass rate | 95% CI |\n| --- | --- | --- | --- |\n"
      <> string.join(tags, "\n"),
    case failures {
      [] -> "## Failing checks\n\nEvery check passed."
      _ -> "## Failing checks\n\n" <> string.join(failures, "\n")
    },
  ]
  |> string.join("\n\n")
  |> string.append("\n")
}

/// One trial in markdown, what was asked, what happened and how it was graded.
pub fn trial(task: task.Task, trial: Trial) -> String {
  let checks =
    list.map(trial.graded, fn(graded) {
      let #(verdict, detail) = verdict_parts(graded.verdict)
      "- **"
      <> verdict
      <> "** "
      <> task.describe(graded.check)
      <> ": "
      <> one_line(detail)
    })
  [
    "# " <> task.name <> ", trial " <> int.to_string(trial.number),
    task.description,
    case trial.passed {
      True -> "Passed, score " <> stats.percent(trial.score) <> "."
      False -> "Failed, score " <> stats.percent(trial.score) <> "."
    },
    "## Checks\n\n" <> string.join(checks, "\n"),
    render.transcript(trial.transcript),
  ]
  |> string.join("\n\n")
  |> string.append("\n")
}

/// A comparison of two runs in markdown, first minus second.
pub fn comparison(
  first: #(Header, Summary),
  second: #(Header, Summary),
) -> String {
  let comparison = summary.compare(first.1, second.1)
  let difference = comparison.difference
  let #(low, high) = stats.interval(difference)
  let rows =
    list.map(comparison.tasks, fn(task) {
      let #(name, a, b) = task
      "| "
      <> name
      <> " | "
      <> stats.percent(a)
      <> " | "
      <> stats.percent(b)
      <> " | "
      <> stats.points(a -. b)
      <> " |"
    })
  let name = fn(header: Header) {
    "`" <> header.context <> "` with `" <> header.model <> "`"
  }
  [
    "# " <> { first.0 }.suite <> ": comparison",
    "A is " <> name(first.0) <> ", B is " <> name(second.0) <> ".",
    "A minus B is **"
      <> stats.points(difference.mean)
      <> "** (95% CI "
      <> case difference.samples < 2 {
      True -> "insufficient tasks"
      False -> stats.points(low) <> " to " <> stats.points(high)
    }
      <> ") over "
      <> int.to_string(difference.samples)
      <> " paired tasks, "
      <> case stats.significant(difference) {
      True -> "a significant difference."
      False -> "not a significant difference."
    },
    "| Task | A | B | A − B |\n| --- | --- | --- | --- |\n"
      <> string.join(rows, "\n"),
    "Better with A: "
      <> list_or_none(comparison.improved)
      <> "\n\nBetter with B: "
      <> list_or_none(comparison.regressed),
  ]
  |> string.join("\n\n")
  |> string.append("\n")
}

fn list_or_none(names) {
  case names {
    [] -> "none."
    _ -> string.join(names, ", ") <> "."
  }
}

fn range(low, high) {
  stats.percent(float.max(low, 0.0))
  <> "–"
  <> stats.percent(float.min(high, 1.0))
}

fn decimal(value: Float) {
  float.to_string(float.to_precision(value, 1))
}

fn one_line(text) {
  let text = string.replace(text, "\n", " ")
  case string.length(text) > 300 {
    True -> string.slice(text, 0, 300) <> "…"
    False -> text
  }
}

/// A judged check of one trial, as written in a log.
pub type Judged {
  Judged(task: String, trial: Int, criterion: String, verdict: String)
}

/// Every judged check of a log, to calibrate a judge against your own labels.
pub fn judged_decoder() -> decode.Decoder(List(Judged)) {
  use trials <- decode.field(
    "trials",
    decode.list({
      use task <- decode.field("task", decode.string)
      use trial <- decode.field("number", decode.int)
      use checks <- decode.field(
        "checks",
        decode.list({
          use check <- decode.field("check", decode.string)
          use verdict <- decode.field("verdict", decode.string)
          decode.success(#(check, verdict))
        }),
      )
      decode.success(
        list.filter_map(checks, fn(check) {
          case check.0 {
            "judged: " <> criterion ->
              Ok(Judged(task:, trial:, criterion:, verdict: check.1))
            _ -> Error(Nil)
          }
        }),
      )
    }),
  )
  decode.success(list.flatten(trials))
}
