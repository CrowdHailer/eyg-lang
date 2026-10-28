//// A trial is one attempt at a task: a fresh session, graded.
////
//// Every trial starts from the same environment, context and workspace, no
//// state is shared between trials.

import gleam/float
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option}
import gleam/time/duration
import gleam/time/timestamp
import overlay/eval/agent
import overlay/eval/environment.{type Environment, Environment}
import overlay/eval/grade.{type Graded}
import overlay/eval/model.{type Model}
import overlay/eval/session
import overlay/eval/task.{type Task}
import overlay/eval/transcript.{type Transcript}

pub type Trial {
  Trial(
    task: String,
    // Trials of a task are numbered from 1.
    number: Int,
    transcript: Transcript,
    graded: List(Graded),
    passed: Bool,
    score: Float,
    milliseconds: Int,
  )
}

/// The session a task starts.
pub fn session(
  environment: Environment,
  context: session.Context,
  model: Model,
  task: Task,
) -> session.Config {
  session.Config(
    environment: Environment(
      ..environment,
      routes: list.append(task.routes, environment.routes),
    ),
    context:,
    model:,
    workspace: task.workspace,
    prompts: task.prompts,
    max_model_calls: task.max_model_calls,
  )
}

/// Run and grade one attempt at a task.
pub fn run(
  environment: Environment,
  context: session.Context,
  model: Model,
  judge: Option(Model),
  task: Task,
  number: Int,
) -> Promise(Trial) {
  let start = timestamp.system_time()
  use transcript <- promise.await(
    session.run(session(environment, context, model, task)),
  )
  let milliseconds =
    timestamp.difference(start, timestamp.system_time())
    |> duration.to_seconds
    |> fn(seconds) { seconds *. 1000.0 }
    |> float.truncate
  use graded <- promise.map(grade.task(task, transcript, environment.hub, judge))
  Trial(
    task: task.name,
    number:,
    transcript:,
    graded:,
    passed: grade.passed(graded),
    score: grade.score(graded),
    milliseconds:,
  )
}

/// A model that follows the task's reference solution.
pub fn oracle(task: Task) -> Model {
  model.Scripted(agent.scripted(task.reference))
}
