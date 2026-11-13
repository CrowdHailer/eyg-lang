import eyg/interpreter/value
import gleam/javascript/promise
import gleam/list
import gleam/string
import overlay/eval
import overlay/eval/agent
import overlay/eval/environment
import overlay/eval/fixture/hub
import overlay/eval/module
import overlay/eval/session
import overlay/eval/suite
import overlay/eval/task

pub fn validation_reports_faults_in_later_contexts_test() {
  let assert Ok(hub) =
    hub.publish_directory(hub.new(), "test/fixtures/packages")
  let assert Ok(suite) = suite.load("test/fixtures/suites/example.eyg", hub)
  let assert Ok(task) =
    list.find(suite.tasks, fn(task) { task.name == "greet" })
  let task =
    task.Task(
      ..task,
      checks: [task.Computes(value.String("Hello, Ada"))],
      reference: [
        [
          agent.Reply("", ["context.hello(\"Ada\")"]),
          agent.Reply("Hello, Ada", []),
        ],
      ],
    )
  let suite = suite.Suite(..suite, tasks: [task])
  let assert Ok(context) =
    module.load("test/fixtures/packages/greeting/index.eyg")
  let environment = environment.Environment(..environment.empty(), hub:)
  use problems <- promise.map(
    eval.validate_contexts(environment, suite, [
      #(session.Module(context), "good"),
      #(session.NoContext, "missing"),
    ]),
  )
  assert problems != []
  assert list.all(problems, string.starts_with(_, "missing: greet:"))
}
