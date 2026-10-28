import todomvc/tasks.{Task}

pub fn tasks_are_numbered_in_order_test() {
  let #(tasks, id) = tasks.create(tasks.from_titles(["a"]), "b")
  assert id == 2
  assert tasks.all(tasks) == [Task(1, "a", False), Task(2, "b", False)]
}

pub fn a_task_can_be_renamed_and_completed_test() {
  let assert Ok(tasks) = tasks.rename(tasks.from_titles(["a"]), 1, "b")
  let assert Ok(tasks) = tasks.set_completed(tasks, 1, True)
  assert tasks.all(tasks) == [Task(1, "b", True)]
}

pub fn a_missing_task_is_an_error_test() {
  assert tasks.rename(tasks.new(), 7, "b") == Error(Nil)
  assert tasks.set_completed(tasks.new(), 7, True) == Error(Nil)
}

pub fn clearing_removes_completed_tasks_test() {
  let assert Ok(tasks) =
    tasks.set_completed(tasks.from_titles(["a", "b"]), 1, True)
  assert tasks.all(tasks.clear_completed(tasks)) == [Task(2, "b", False)]
}
