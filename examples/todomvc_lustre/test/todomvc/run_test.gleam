import eyg/embed/shell.{Returned}
import eyg/interpreter/value as v
import gleam/dict
import gleam/option.{Some}
import todomvc/fixture
import todomvc/run.{Run}
import todomvc/tasks.{Task}

fn value(code) {
  let result = run.run(fixture.shell(), fixture.tasks(), code)
  case result.outcome {
    Returned(Some(value)) -> value
    other -> panic as shell.report(result.printed, other)
  }
}

pub fn a_query_can_use_the_standard_library_test() {
  assert value(
      "@standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja.list.length(todos.all({}))",
    )
    == v.Integer(4)
}

pub fn tasks_can_be_found_by_tag_test() {
  assert value(
      "let {list} = @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja\nlist.map(todos.tagged(\"#shopping\"), (task) -> { task.id })",
    )
    == v.LinkedList([v.Integer(1), v.Integer(3)])
}

pub fn tasks_can_be_matched_ignoring_case_test() {
  assert value(
      "let {list} = @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja\nlist.map(todos.matching(\"BUY\"), (task) -> { task.title })",
    )
    == v.LinkedList([
      v.String("Buy milk #shopping"),
      v.String("Buy bread #shopping"),
    ])
}

pub fn a_program_can_change_many_tasks_at_once_test() {
  let Run(tasks:, outcome:, ..) =
    run.run(
      fixture.shell(),
      fixture.tasks(),
      "let {list} = @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja\nlist.map(todos.tagged(\"#shopping\"), todos.complete)",
    )
  let assert Returned(_) = outcome
  assert tasks.all(tasks)
    == [
      Task(1, "Buy milk #shopping", True),
      Task(2, "Call the plumber", False),
      Task(3, "Buy bread #shopping", True),
      Task(4, "Write the EYG post #work", False),
    ]
}

pub fn a_program_can_create_tasks_test() {
  let Run(tasks:, outcome:, ..) =
    run.run(fixture.shell(), fixture.tasks(), "todos.add(\"Book dentist\")")
  let assert Returned(Some(id)) = outcome
  assert id == v.Integer(5)
  let assert [_, _, _, _, Task(5, "Book dentist", False)] = tasks.all(tasks)
}

pub fn deleting_is_not_an_effect_test() {
  let assert Run(outcome: shell.TypeFailed(reasons), ..) =
    run.run(fixture.shell(), fixture.tasks(), "perform DeleteTask(1)")
  assert reasons == ["line 1: missing row 'DeleteTask'"]
}

pub fn a_package_that_is_not_loaded_is_a_type_error_test() {
  let assert Run(outcome: shell.TypeFailed(_), ..) =
    run.run(fixture.shell(), fixture.tasks(), "@json")
}

pub fn tags_can_be_counted_test() {
  assert value(
      "let {list} = @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja
let tags = list.fold(list.flat_map(todos.all({}), todos.tags), [], (tag, seen) -> {
  match list.contains(seen, tag) {
    True(_) -> { seen }
    False(_) -> { [tag, ..seen] }
  }
})
list.map(tags, (tag) -> { {tag, count: list.length(todos.tagged(tag))} })",
    )
    == v.LinkedList([record("#work", 1), record("#shopping", 2)])
}

pub fn titles_can_be_rewritten_test() {
  let Run(tasks:, ..) =
    run.run(
      fixture.shell(),
      fixture.tasks(),
      "let {list, string} = @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja
list.map(todos.matching(\"plumber\"), (task) -> { todos.rename(task, string.append(\"Urgent: \", task.title)) })",
    )
  let assert [_, Task(2, "Urgent: Call the plumber", False), ..] =
    tasks.all(tasks)
}

fn record(tag, count) {
  v.Record(
    dict.from_list([#("tag", v.String(tag)), #("count", v.Integer(count))]),
  )
}

pub fn active_completed_and_reopened_tasks_share_the_same_model_test() {
  let result =
    run.run(
      fixture.shell(),
      fixture.tasks(),
      "let _ = todos.complete({id: 1}) {active: @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja.list.length(todos.active({})), completed: @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja.list.length(todos.completed({}))}",
    )
  let assert Returned(Some(v.Record(fields))) = result.outcome
  assert dict.get(fields, "active") == Ok(v.Integer(3))
  assert dict.get(fields, "completed") == Ok(v.Integer(1))
  let result = run.run(result.shell, result.tasks, "todos.reopen({id: 1})")
  assert result.outcome == Returned(Some(v.ok(v.unit())))
  let assert [Task(1, _, False), ..] = tasks.all(result.tasks)
}

pub fn missing_tasks_reply_with_not_found_and_printing_is_collected_test() {
  assert value("todos.rename({id: 99}, \"missing\")")
    == v.error(v.Tagged("NotFound", v.unit()))
  assert value("todos.complete({id: 99})")
    == v.error(v.Tagged("NotFound", v.unit()))
  let result =
    run.run(
      fixture.shell(),
      fixture.tasks(),
      "let _ = perform Print(\"first\") let _ = perform Print(\"second\") 42",
    )
  assert result.printed == ["first", "second"]
  assert result.outcome == Returned(Some(v.Integer(42)))
}
