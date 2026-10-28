import gleam/list
import overlay/eval/evaluate
import overlay/eval/fixture/hub
import overlay/eval/module
import overlay/eval/suite
import overlay/eval/task

pub fn task_modules_load_in_name_order_test() {
  let assert Ok(hub) =
    hub.publish_directory(hub.new(), "test/fixtures/packages")
  let assert Ok(suite) = suite.load("test/fixtures/suites/example.eyg", hub)
  assert ["add", "fact", "greet", "note", "project", "quiet"]
    == list.map(suite.tasks, fn(task) { task.name })
}

pub fn tasks_cannot_pass_without_checks_or_run_without_a_budget_test() {
  list.each(
    [
      "{description: \"empty\", prompts: [\"hi\"], checks: []}",
      "{description: \"empty\", prompts: [], checks: [Computes(1)]}",
      "{description: \"zero\", prompts: [\"hi\"], checks: [Computes(1)], max_model_calls: 0}",
    ],
    fn(code) {
      let assert Ok(loaded) = module.from_source(code, ".")
      let assert Ok(value) = evaluate.module(loaded, hub.new())
      let assert Error(_) = task.decode("invalid", value)
    },
  )
}
