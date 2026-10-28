//// Run EYG against the todo list, in a shell from `eyg_embed` whose effects
//// are the task effects and whose packages come from the hub cache.

import eyg/embed/shell.{type Shell}
import eyg/hub/cache.{type Cache}
import eyg/interpreter/value as v
import gleam/list
import gleam/result
import todomvc/effect
import todomvc/tasks.{type Tasks}

pub type Run {
  Run(shell: Shell, tasks: Tasks, printed: List(String), outcome: shell.Outcome)
}

/// A shell with the library in scope as `todos`, the packages it refers to
/// must be in the cache.
pub fn start(
  library: String,
  cache: Cache(shell.Span),
) -> Result(Shell, String) {
  shell.new(effect.types())
  |> shell.with_references(fn(reference) {
    cache.get_reference(cache, reference)
    |> result.map(fn(module) { shell.Module(module.value, module.type_) })
  })
  |> shell.with_module("todos", library)
}

pub fn run(shell: Shell, tasks: Tasks, code: String) -> Run {
  let shell.Run(shell:, state: #(tasks, printed), outcome:) =
    shell.run(shell, code, #(tasks, []), handle)
  Run(shell:, tasks:, printed: list.reverse(printed), outcome:)
}

/// What a person, or the agent, is told about a run.
pub fn report(run: Run) -> String {
  shell.report(run.printed, run.outcome)
}

fn handle(state, label, lift) {
  let #(tasks, printed) = state
  case effect.cast(label, lift) {
    Ok(effect.Print(line)) -> Ok(#(#(tasks, [line, ..printed]), v.unit()))
    Ok(request) -> {
      let #(tasks, reply) = effect.handle(tasks, request)
      Ok(#(#(tasks, printed), reply))
    }
    Error(_) -> Error("not a " <> label)
  }
}
