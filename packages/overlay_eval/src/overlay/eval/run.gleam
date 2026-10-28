//// A run is every trial of a suite, with one model and one context.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option}
import gleam/time/calendar
import gleam/time/timestamp
import overlay/eval/environment.{type Environment}
import overlay/eval/model.{type Model}
import overlay/eval/session
import overlay/eval/suite.{type Suite}
import overlay/eval/task.{type Task}
import overlay/eval/trial.{type Trial}

pub type Config {
  Config(
    suite: Suite,
    environment: Environment,
    context: session.Context,
    // How the context is named in reports, such as its path.
    context_name: String,
    model: Model,
    // Checks are judged by this model, judged checks are unknown without one.
    judge: Option(Model),
    trials: Int,
    // The model for a trial, so each trial can record or replay separately.
    model_for: fn(Task, Int) -> Model,
    judge_for: fn(Task, Int) -> Option(Model),
  )
}

pub type Run {
  Run(
    // When the run started, RFC 3339.
    started: String,
    suite: String,
    context: String,
    model: String,
    judge: String,
    trials_per_task: Int,
    tasks: List(Task),
    trials: List(Trial),
  )
}

/// The configuration for a run where every trial uses the same models.
pub fn config(
  suite: Suite,
  environment: Environment,
  context: session.Context,
  context_name: String,
  model: Model,
  judge: Option(Model),
  trials: Int,
) -> Config {
  Config(
    suite:,
    environment:,
    context:,
    context_name:,
    model:,
    judge:,
    trials:,
    model_for: fn(_, _) { model },
    judge_for: fn(_, _) { judge },
  )
}

/// Run every trial of every task in order, `progress` is told of each one.
pub fn run(config: Config, progress: fn(Trial) -> Nil) -> Promise(Run) {
  let started =
    timestamp.to_rfc3339(timestamp.system_time(), calendar.utc_offset)
  let attempts =
    list.flat_map(config.suite.tasks, fn(task) {
      int.range(from: 1, to: config.trials + 1, with: [], run: fn(acc, number) {
        [#(task, number), ..acc]
      })
      |> list.reverse
    })
  use trials <- promise.map(
    list.fold(attempts, promise.resolve([]), fn(done, attempt) {
      use done <- promise.await(done)
      let #(task, number) = attempt
      use trial <- promise.map(trial.run(
        config.environment,
        config.context,
        config.model_for(task, number),
        config.judge_for(task, number),
        task,
        number,
      ))
      progress(trial)
      [trial, ..done]
    }),
  )
  Run(
    started:,
    suite: config.suite.name,
    context: config.context_name,
    model: model.describe(config.model),
    judge: option.map(config.judge, model.describe) |> option.unwrap("none"),
    trials_per_task: config.trials,
    tasks: config.suite.tasks,
    trials: list.reverse(trials),
  )
}
