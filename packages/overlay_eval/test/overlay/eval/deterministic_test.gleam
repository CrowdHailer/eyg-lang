import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import overlay/eval/agent
import overlay/eval/environment
import overlay/eval/fixture/hub
import overlay/eval/grade
import overlay/eval/model
import overlay/eval/module
import overlay/eval/session
import overlay/eval/suite
import overlay/eval/task
import overlay/eval/trial

pub fn reference_solutions_pass_and_empty_replies_fail_test() {
  let assert Ok(hub) =
    hub.publish_directory(hub.new(), "test/fixtures/packages")
  let assert Ok(suite) = suite.load("test/fixtures/suites/example.eyg", hub)
  let assert Ok(context) =
    module.load("test/fixtures/packages/greeting/index.eyg")
  let env = environment.Environment(..environment.empty(), hub:)
  list.fold(suite.tasks, promise.resolve(Nil), fn(done, task) {
    use Nil <- promise.await(done)
    let checks =
      list.filter(task.checks, fn(check) {
        case check {
          task.Judged(_) -> False
          _ -> True
        }
      })
    let task = task.Task(..task, checks:)
    use solved <- promise.await(trial.run(
      env,
      session.Module(context),
      trial.oracle(task),
      None,
      task,
      1,
    ))
    list.each(solved.graded, fn(graded) {
      let assert grade.Pass(_) = graded.verdict
    })
    use empty <- promise.map(trial.run(
      env,
      session.Module(context),
      model.Scripted(agent.null()),
      None,
      task,
      1,
    ))
    assert !empty.passed
  })
}
