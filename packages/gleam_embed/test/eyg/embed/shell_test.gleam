import eyg/analysis/type_/isomorphic as t
import eyg/embed/shell.{Module, Returned, Run}
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/javascript/promise
import gleam/option.{None, Some}

// A counter: `Add(n)` adds to the total and returns it, `Print` is collected.
type Counter {
  Counter(total: Int, printed: List(String))
}

fn counter() {
  shell.new([
    #("Add", #(t.Integer, t.Integer)),
    #("Print", #(t.String, t.unit)),
  ])
}

fn handle(counter: Counter, label, lift) {
  case label, lift {
    "Add", v.Integer(n) -> {
      let total = counter.total + n
      Ok(#(Counter(..counter, total:), v.Integer(total)))
    }
    "Print", v.String(line) ->
      Ok(#(Counter(..counter, printed: [line, ..counter.printed]), v.unit()))
    _, _ -> Error("unexpected")
  }
}

fn run(shell, code) {
  shell.run(shell, code, Counter(0, []), handle)
}

pub fn a_run_returns_its_last_expression_test() {
  let Run(outcome:, ..) = run(counter(), "!int_add(1, 2)")
  assert outcome == Returned(Some(v.Integer(3)))
}

pub fn effects_are_answered_by_the_host_test() {
  let Run(state:, outcome:, ..) =
    run(counter(), "let _ = perform Print(\"hi\")\nperform Add(2)")
  assert state == Counter(2, ["hi"])
  assert outcome == Returned(Some(v.Integer(2)))
}

pub fn dependent_bindings_and_effects_keep_lexical_order_test() {
  let Run(state:, outcome:, ..) =
    run(counter(), "let a = perform Add(2) let b = perform Add(a) b")
  assert state.total == 4
  assert outcome == Returned(Some(v.Integer(4)))
}

pub fn destructuring_and_shadowing_retain_the_final_bindings_test() {
  let Run(shell:, outcome:, ..) =
    run(
      counter(),
      "let x = 1 let x = !int_add(x, 1) let {answer} = {answer: x} answer",
    )
  assert outcome == Returned(Some(v.Integer(2)))
  let Run(outcome:, ..) = run(shell, "!int_add(answer, 1)")
  assert outcome == Returned(Some(v.Integer(3)))
  let Run(outcome:, ..) =
    run(
      counter(),
      "let {left, right} = {left: 1, right: 2} !int_add(left, right)",
    )
  assert outcome == Returned(Some(v.Integer(3)))
}

pub fn variables_and_their_types_are_kept_test() {
  let Run(shell:, outcome:, ..) =
    run(counter(), "let a = 5\nlet id = (x) -> { x }")
  assert outcome == Returned(None)
  let Run(outcome:, ..) = run(shell, "let _ = id(\"s\")\n!int_add(id(a), 1)")
  assert outcome == Returned(Some(v.Integer(6)))
  let Run(outcome:, ..) = run(shell, "!string_append(a, \"x\")")
  assert outcome
    == shell.TypeFailed([
      "line 1: type mismatch given: Integer expected: String",
    ])
}

pub fn an_effect_the_host_does_not_offer_does_not_run_test() {
  let Run(state:, outcome:, ..) =
    run(counter(), "let _ = perform Add(1)\nperform Launch({})")
  assert state == Counter(0, [])
  assert outcome == shell.TypeFailed(["line 2: missing row 'Launch'"])
}

pub fn a_parse_error_is_reported_test() {
  let Run(outcome:, ..) = run(counter(), "let = ")
  let assert shell.ParseFailed(_) = outcome
}

pub fn a_refused_effect_stops_the_program_and_keeps_the_scope_test() {
  let Run(shell:, ..) = run(counter(), "let a = 1")
  let Run(shell:, state:, outcome:) =
    shell.run(
      shell,
      "let _ = perform Add(1)\nperform Add(2)",
      Counter(0, []),
      fn(counter, label, lift) {
        case counter.total {
          0 -> handle(counter, label, lift)
          _ -> Error("full")
        }
      },
    )
  assert state.total == 1
  assert outcome == shell.Stopped("Add failed: full")
  assert shell.lookup(shell, "a") == Ok(v.Integer(1))
}

const library =
  "let double = (x) -> { perform Add(x) }
{readme: \"Adds things\", double: double, twice: (f, x) -> { f(f(x)) }}"

pub fn a_library_is_in_scope_and_its_functions_perform_effects_test() {
  let assert Ok(shell) = shell.with_module(counter(), "lib", library)
  assert shell.text(shell, "lib", "readme") == "Adds things"
  let Run(shell:, state:, outcome:) = run(shell, "lib.double(3)")
  assert #(state.total, outcome) == #(3, Returned(Some(v.Integer(3))))
  // An effect inside a library function leaves the shell's scope intact.
  let Run(outcome:, ..) =
    run(shell, "let _ = lib.double(1)\nlib.twice((x) -> { x }, 7)")
  assert outcome == Returned(Some(v.Integer(7)))
}

pub fn a_module_cannot_perform_effects_while_it_is_built_test() {
  let assert Error(_) = shell.with_module(counter(), "lib", "perform Add(1)")
}

pub fn references_are_resolved_for_types_and_values_test() {
  let five = Module(value: v.Integer(5), type_: t.Integer)
  let shell =
    counter()
    |> shell.with_references(fn(reference) {
      case reference {
        ir.Package("five") -> Ok(five)
        _ -> Error(Nil)
      }
    })
  let Run(outcome:, ..) = run(shell, "!int_add(@five, 1)")
  assert outcome == Returned(Some(v.Integer(6)))
  let Run(outcome:, ..) = run(shell, "@six")
  let assert shell.TypeFailed(_) = outcome
}

pub fn a_report_says_what_happened_test() {
  assert shell.report([], Returned(Some(v.Integer(1)))) == "1"
  assert shell.report(["a", "b"], Returned(None))
    == "Printed:\na\nb\nReturned:\n{}"
  assert shell.report([], shell.TypeFailed(["line 1: x"]))
    == "The code did not type check, nothing ran.\nline 1: x"
}

pub fn an_async_handler_can_answer_effects_test() {
  use Run(state:, outcome:, ..) <- promise.map(
    shell.run_async(counter(), "perform Add(4)", Counter(0, []), fn(c, l, x) {
      promise.resolve(handle(c, l, x))
    }),
  )
  assert #(state.total, outcome) == #(4, Returned(Some(v.Integer(4))))
}
