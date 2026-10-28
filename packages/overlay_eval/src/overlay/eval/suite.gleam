//// A suite is a set of tasks written as one EYG module.
////
//// The module is a record, each field is a task named by its label. Records
//// let tasks expect values of different types, a list could not.
////
//// ```eyg
//// {
////   add: {description: "Add", prompts: ["2 + 3?"], checks: [Computes(5)]},
////   greet: import "./greet.eyg",
//// }
//// ```

import eyg/interpreter/cast
import eyg/interpreter/simple_debug
import filepath
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import overlay/eval/evaluate
import overlay/eval/fixture/hub.{type Hub}
import overlay/eval/module
import overlay/eval/task.{type Task}

pub type Suite {
  Suite(name: String, tasks: List(Task))
}

/// Load the suite in a module, packages it references come from the hub.
pub fn load(path: String, hub: Hub) -> Result(Suite, String) {
  use loaded <- result.try(module.load(path))
  use value <- result.try(evaluate.module(loaded, hub))
  use fields <- result.try(
    cast.as_record(value)
    |> result.map_error(fn(reason) {
      path <> " is not a record of tasks: " <> simple_debug.describe(reason)
    }),
  )
  use tasks <- result.map(
    dict.to_list(fields)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.try_map(fn(field) { task.decode(field.0, field.1) }),
  )
  let name = filepath.base_name(path) |> string.replace(".eyg", "")
  Suite(name:, tasks:)
}

/// Keep the tasks with any of the tags, all tasks when no tags are given.
pub fn tagged(suite: Suite, tags: List(String)) -> Suite {
  case tags {
    [] -> suite
    _ ->
      Suite(
        ..suite,
        tasks: list.filter(suite.tasks, fn(task) {
          list.any(task.tags, list.contains(tags, _))
        }),
      )
  }
}
