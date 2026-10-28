//// The effects an EYG program can perform on the todo list.
//// Programs can read, create and change tasks. Deleting is left to the page.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/result.{try}
import todomvc/tasks.{type Task}
import touch_grass
import touch_grass/interface.{type Harness, Interface}

pub type Effect {
  ListTasks
  CreateTask(title: String)
  RenameTask(id: Int, title: String)
  SetCompleted(id: Int, completed: Bool)
  Print(String)
}

fn task_type() {
  t.record([#("id", t.Integer), #("title", t.String), #("completed", t.boolean)])
}

fn not_found() {
  t.union([#("NotFound", t.unit)])
}

pub fn harness() -> Harness(Effect, a) {
  [
    Interface("ListTasks", t.unit, t.List(task_type()), cast.as_unit(
      _,
      ListTasks,
    )),
    Interface("CreateTask", t.String, t.Integer, fn(value) {
      use title <- try(cast.as_string(value))
      Ok(CreateTask(title))
    }),
    Interface(
      "RenameTask",
      t.record([#("id", t.Integer), #("title", t.String)]),
      t.result(t.unit, not_found()),
      fn(value) {
        use id <- try(cast.field("id", cast.as_integer, value))
        use title <- try(cast.field("title", cast.as_string, value))
        Ok(RenameTask(id:, title:))
      },
    ),
    Interface(
      "SetCompleted",
      t.record([#("id", t.Integer), #("completed", t.boolean)]),
      t.result(t.unit, not_found()),
      fn(value) {
        use id <- try(cast.field("id", cast.as_integer, value))
        use completed <- try(cast.field("completed", as_bool, value))
        Ok(SetCompleted(id:, completed:))
      },
    ),
    touch_grass.print() |> touch_grass.map(Print),
  ]
}

fn as_bool(value) {
  cast.as_variant(value, [
    #("True", cast.as_unit(_, True)),
    #("False", cast.as_unit(_, False)),
  ])
}

pub fn task(task: Task) {
  v.Record(
    dict.from_list([
      #("id", v.Integer(task.id)),
      #("title", v.String(task.title)),
      #("completed", v.bool(task.completed)),
    ]),
  )
}

pub fn task_list(tasks: List(Task)) {
  v.LinkedList(list.map(tasks, task))
}

pub fn found(result: Result(a, Nil)) {
  case result {
    Ok(_) -> v.ok(v.unit())
    Error(Nil) -> v.error(v.Tagged("NotFound", v.unit()))
  }
}

pub fn cast(label, lift) {
  interface.cast(harness(), label, lift)
}

pub fn types() {
  interface.types(harness())
}

/// Carry out one effect.
pub fn handle(tasks, effect) -> #(tasks.Tasks, v.Value(m, c)) {
  case effect {
    ListTasks -> #(tasks, task_list(tasks.all(tasks)))
    CreateTask(title:) -> {
      let #(tasks, id) = tasks.create(tasks, title)
      #(tasks, v.Integer(id))
    }
    RenameTask(id:, title:) ->
      case tasks.rename(tasks, id, title) {
        Ok(updated) -> #(updated, found(Ok(Nil)))
        Error(Nil) -> #(tasks, found(Error(Nil)))
      }
    SetCompleted(id:, completed:) ->
      case tasks.set_completed(tasks, id, completed) {
        Ok(updated) -> #(updated, found(Ok(Nil)))
        Error(Nil) -> #(tasks, found(Error(Nil)))
      }
    Print(_) -> #(tasks, v.unit())
  }
}
