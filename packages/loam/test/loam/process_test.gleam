import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/process
import eyg/interpreter/value as v
import gleam/list
import gleam/option.{Some}
import loam/source

pub fn pure_runaway_yields_and_does_not_prevent_other_agents_running_test() {
  let assert Ok(infinite) =
    source.parse("!fix((self, x) -> { self(x) })(0)", source.Inline)
  let assert Ok(finite) = source.parse("!int_add(20, 22)", source.Inline)
  let runaway = process.start(infinite, [])
  let completed = process.start(finite, [])
  let assert process.Yielded(runaway) = process.slice(runaway, 100)
  let assert process.Returned(Some(v.Integer(42)), _) =
    process.slice(completed, 100)
  let assert process.Yielded(_) = process.slice(runaway, 100)
  // The bounded compatibility runner stops a pure loop without needing an IO effect.
  let assert Error(#(break.UnhandledEffect("ExecutionLimit", _), _, _, _)) =
    block.execute(infinite, [])
}

pub fn slicing_preserves_scope_and_answers_test() {
  let assert Ok(node) =
    source.parse("let a = 20 !int_add(a, 22)", source.Inline)
  let sliced = finish(process.start(node, []))
  let assert process.Returned(Some(v.Integer(42)), scope) = sliced
  assert list.key_find(scope, "a") == Ok(v.Integer(20))
}

fn finish(task) {
  case process.slice(task, 1) {
    process.Yielded(task) -> finish(task)
    completed -> completed
  }
}
