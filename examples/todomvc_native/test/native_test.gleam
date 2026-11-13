import gleam/dynamic
import gleam/javascript/promise
import gleam/list
import gleam/string
import native/run
import simplifile
import todomvc/tasks

fn start() {
  let assert Ok(cwd) = simplifile.current_directory()
  run.start_at(
    cwd <> "/../../packages/embed_js/dist/eyg.mjs",
    "{readme: \"Todo host\"}",
    "",
  )
}

pub fn actual_bundle_changes_native_tasks_and_retains_bindings_test() {
  use created <- promise.map(start())
  let assert Ok(shell) = created
  assert run.text(shell, "todos", "readme") == "Todo host"
  let result =
    run.run(shell, tasks.new(), "let id = perform CreateTask(\"Milk\") id")
  assert result.outcome == run.Returned(dynamic.int(1))
  assert list.length(tasks.all(result.tasks)) == 1
  let result =
    run.run(shell, result.tasks, "perform RenameTask({id, title: \"Bread\"})")
  assert run.report(result) == "Ok({})"
  assert tasks.all(result.tasks) == [tasks.Task(1, "Bread", False)]
  let result =
    run.run(
      shell,
      result.tasks,
      "perform SetCompleted({id, completed: True({})})",
    )
  assert tasks.all(result.tasks) == [tasks.Task(1, "Bread", True)]
  let result = run.run(shell, result.tasks, "perform ListTasks({})")
  assert string.contains(result.output, "Bread")
  assert string.contains(result.output, "True({})")
}

pub fn unavailable_effects_and_wrong_types_run_no_host_callbacks_test() {
  use created <- promise.map(start())
  let assert Ok(shell) = created
  let initial = tasks.from_titles(["Milk"])
  let result =
    run.run(
      shell,
      initial,
      "let _ = perform CreateTask(\"Ignored\") perform DeleteTask(1)",
    )
  assert string.contains(result.output, "nothing ran")
  assert result.tasks == initial
  let result =
    run.run(
      shell,
      initial,
      "perform SetCompleted({id: \"1\", completed: True({})})",
    )
  assert string.contains(result.output, "nothing ran")
  assert result.tasks == initial
}

pub fn missing_ids_are_tagged_plain_replies_and_print_is_unit_test() {
  use created <- promise.map(start())
  let assert Ok(shell) = created
  let result =
    run.run(
      shell,
      tasks.new(),
      "perform RenameTask({id: 99, title: \"Missing\"})",
    )
  assert result.output == "Error(NotFound({}))"
  let result =
    run.run(
      shell,
      tasks.new(),
      "perform SetCompleted({id: 99, completed: False({})})",
    )
  assert result.output == "Error(NotFound({}))"
  let result =
    run.run(shell, tasks.new(), "let _ = perform Print(\"Hello\") 42")
  assert result.output == "Hello\n42"
}
