//// The todo list, the same for the page and for EYG programs.

import gleam/list

pub type Task {
  Task(id: Int, title: String, completed: Bool)
}

pub type Tasks {
  Tasks(items: List(Task), next: Int)
}

pub fn new() -> Tasks {
  Tasks(items: [], next: 1)
}

pub fn from_titles(titles: List(String)) -> Tasks {
  list.fold(titles, new(), fn(tasks, title) { create(tasks, title).0 })
}

/// Oldest first.
pub fn all(tasks: Tasks) -> List(Task) {
  tasks.items
}

pub fn create(tasks: Tasks, title: String) -> #(Tasks, Int) {
  let Tasks(items:, next:) = tasks
  let task = Task(id: next, title:, completed: False)
  #(Tasks(items: list.append(items, [task]), next: next + 1), next)
}

fn update(tasks: Tasks, id: Int, f: fn(Task) -> Task) -> Result(Tasks, Nil) {
  case list.any(tasks.items, fn(task) { task.id == id }) {
    True ->
      Ok(
        Tasks(
          ..tasks,
          items: list.map(tasks.items, fn(task) {
            case task.id == id {
              True -> f(task)
              False -> task
            }
          }),
        ),
      )
    False -> Error(Nil)
  }
}

pub fn rename(tasks: Tasks, id: Int, title: String) -> Result(Tasks, Nil) {
  update(tasks, id, fn(task) { Task(..task, title:) })
}

pub fn set_completed(tasks: Tasks, id: Int, completed: Bool) {
  update(tasks, id, fn(task) { Task(..task, completed:) })
}

pub fn delete(tasks: Tasks, id: Int) -> Tasks {
  Tasks(..tasks, items: list.filter(tasks.items, fn(task) { task.id != id }))
}

pub fn clear_completed(tasks: Tasks) -> Tasks {
  Tasks(..tasks, items: list.filter(tasks.items, fn(task) { !task.completed }))
}

pub fn complete_all(tasks: Tasks, completed: Bool) -> Tasks {
  let items = list.map(tasks.items, fn(task) { Task(..task, completed:) })
  Tasks(..tasks, items:)
}
