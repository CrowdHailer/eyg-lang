//// Summaries of runs and comparisons between them.

import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import overlay/eval/grade
import overlay/eval/run.{type Run}
import overlay/eval/stats.{type Estimate}
import overlay/eval/task
import overlay/eval/transcript

pub type TaskResult {
  TaskResult(
    name: String,
    tags: List(String),
    trials: Int,
    passes: Int,
    // pass@1, the share of trials that passed.
    rate: Float,
    // The mean share of checks passed, partial credit.
    score: Float,
    // At least one of the trials passes.
    pass_at_k: Float,
    // Every one of the trials passes.
    pass_power_k: Float,
    model_calls: Float,
    // Programs that did not compute a value: type errors, exceptions and aborts.
    failed_runs: Float,
    milliseconds: Float,
  )
}

pub type Summary {
  Summary(
    tasks: List(TaskResult),
    // Means over tasks, errors clustered by task.
    rate: Estimate,
    score: Estimate,
    tags: List(#(String, Estimate)),
    // The checks that failed, how often, with an example reason.
    failures: List(Failure),
  )
}

pub type Failure {
  Failure(task: String, check: String, count: Int, reason: String)
}

pub fn summarise(run: Run) -> Summary {
  let k = run.trials_per_task
  let tasks =
    list.map(run.tasks, fn(task) {
      let trials =
        list.filter(run.trials, fn(trial) { trial.task == task.name })
      let count = list.length(trials)
      let passes = list.count(trials, fn(trial) { trial.passed })
      let average = fn(f) { stats.mean(list.map(trials, f)) }
      TaskResult(
        name: task.name,
        tags: task.tags,
        trials: count,
        passes:,
        rate: rate(passes, count),
        score: average(fn(trial) { trial.score }),
        pass_at_k: stats.pass_at_k(count, passes, int.min(k, count)),
        pass_power_k: stats.pass_power_k(count, passes, int.min(k, count)),
        model_calls: average(fn(trial) {
          int.to_float(trial.transcript.model_calls)
        }),
        failed_runs: average(fn(trial) {
          transcript.runs(trial.transcript)
          |> list.count(fn(run) {
            case run.outcome {
              transcript.Computed(..) -> False
              _ -> True
            }
          })
          |> int.to_float
        }),
        milliseconds: average(fn(trial) { int.to_float(trial.milliseconds) }),
      )
    })
  let failures =
    list.flat_map(run.trials, fn(trial) {
      list.filter_map(trial.graded, fn(graded) {
        case graded.verdict {
          grade.Pass(..) -> Error(Nil)
          grade.Fail(reason) | grade.Unknown(reason) ->
            Ok(#(#(trial.task, task.describe(graded.check)), reason))
        }
      })
    })
    |> list.group(fn(failure) { failure.0 })
    |> dict_to_failures
  Summary(
    tasks:,
    rate: stats.estimate(list.map(tasks, fn(task) { task.rate })),
    score: stats.estimate(list.map(tasks, fn(task) { task.score })),
    tags: list.map(task.tags(run.tasks), fn(tag) {
      let tagged =
        list.filter(tasks, fn(task) { list.contains(task.tags, tag) })
      #(tag, stats.estimate(list.map(tagged, fn(task) { task.rate })))
    }),
    failures:,
  )
}

fn dict_to_failures(groups) {
  groups
  |> dict.to_list
  |> list.map(fn(group) {
    let #(#(task, check), failures) = group
    let reason = case list.first(failures) {
      Ok(#(_, reason)) -> reason
      Error(Nil) -> ""
    }
    Failure(task:, check:, count: list.length(failures), reason:)
  })
  |> list.sort(fn(a, b) {
    case int.compare(b.count, a.count) {
      order.Eq -> string.compare(a.task <> a.check, b.task <> b.check)
      order -> order
    }
  })
}

fn rate(passes, trials) {
  case trials {
    0 -> 0.0
    _ -> int.to_float(passes) /. int.to_float(trials)
  }
}

pub type Comparison {
  Comparison(
    // Task, rate in the first run, rate in the second.
    tasks: List(#(String, Float, Float)),
    // First minus second, paired by task.
    difference: Estimate,
    improved: List(String),
    regressed: List(String),
  )
}

/// Compare the pass rates of two summaries on the tasks both ran.
pub fn compare(first: Summary, second: Summary) -> Comparison {
  let tasks =
    list.filter_map(first.tasks, fn(task) {
      case list.find(second.tasks, fn(other) { other.name == task.name }) {
        Ok(other) -> Ok(#(task.name, task.rate, other.rate))
        Error(Nil) -> Error(Nil)
      }
    })
  Comparison(
    tasks:,
    difference: stats.paired(list.map(tasks, fn(task) { #(task.1, task.2) })),
    improved: list.filter_map(tasks, fn(task) {
      case task.1 >. task.2 {
        True -> Ok(task.0)
        False -> Error(Nil)
      }
    }),
    regressed: list.filter_map(tasks, fn(task) {
      case task.1 <. task.2 {
        True -> Ok(task.0)
        False -> Error(Nil)
      }
    }),
  )
}
