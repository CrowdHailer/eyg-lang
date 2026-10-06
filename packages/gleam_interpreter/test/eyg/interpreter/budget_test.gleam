import eyg/interpreter/break
import eyg/interpreter/budget
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value
import eyg/parser

fn start(code) {
  let assert Ok(source) = parser.all_from_string(code)
  budget.start(source, [])
}

pub fn zero_and_negative_budgets_do_not_evaluate_test() {
  let pending = start("perform Host({})")
  assert budget.advance(pending, 0) == budget.Run(pending, 0)
  assert budget.advance(pending, -1) == budget.Run(pending, 0)
}

pub fn completed_runs_do_not_consume_more_steps_test() {
  let budget.Run(next, steps) = start("42") |> budget.advance(10)
  assert steps == 2
  assert next == state.Break(Ok(value.Integer(42)))
  assert budget.advance(next, 10) == budget.Run(next, 0)
}

pub fn unbounded_fact_generation_suspends_without_a_partial_result_test() {
  let source =
    "resolve Number @{
       fact Number(0),
       rule Number(!int_add(n, 1)) { var n Number(n) }
     }"
  let first = start(source) |> budget.advance(500)
  assert first.steps == 500
  let assert state.Loop(_, _, _) = first.next
  let second = budget.advance(first.next, 500)
  assert second.steps == 500
  let assert state.Loop(_, _, _) = second.next
  assert second.next != first.next
}

pub fn nonterminating_pure_predicate_is_also_budgeted_test() {
  let pending =
    start(
      "let forever = !fix((self, x) -> { self(x) })
       resolve Out @{ rule Out(1) { forever({}) } }",
    )
    |> budget.advance(500)
  assert pending.steps == 500
  let assert state.Loop(_, _, _) = pending.next
}

pub fn cyclic_query_resumes_to_the_same_result_as_unlimited_execution_test() {
  let code =
    "resolve Path @{
       fact Edge({from: 1, to: 2}), fact Edge({from: 2, to: 1}),
       rule Path({from, to}) { var from var to Edge({from, to}) }
       rule Path({from, to}) {
         var from var to var middle
         Path({from, to: middle}), Edge({from: middle, to})
       }
     }"
  let assert Ok(source) = parser.all_from_string(code)
  let assert Ok(expected) = expression.execute(source, [])
  let budget.Run(next, spent) = start(code) |> budget.advance(30)
  let assert state.Loop(_, _, _) = next
  assert spent == 30
  let budget.Run(next, spent) = budget.advance(next, 10_000)
  let assert state.Break(Ok(actual)) = next
  assert spent < 10_000
  assert actual == expected
  assert simple_debug.inspect(actual)
    == "[{from: 1, to: 2}, {from: 2, to: 1}, {from: 1, to: 1}, {from: 2, to: 2}]"
}

pub fn hosts_can_account_for_steps_across_effects_test() {
  let first = start("!int_add(perform Host({}), 1)") |> budget.advance(100)
  let assert state.Break(Error(#(break.UnhandledEffect("Host", _), _, env, k))) =
    first.next
  let remaining = 100 - first.steps
  let second =
    budget.advance(state.Loop(state.V(value.Integer(4)), env, k), remaining)
  assert second.next == state.Break(Ok(value.Integer(5)))
  assert first.steps + second.steps <= 100
}
