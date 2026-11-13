import eyg/interpreter/value
import gleam/bit_array
import gleam/dict
import gleam/string
import oas/generator/utils
import overlay/eval/pure
import overlay/llm/chat
import overlay/llm/tool

pub fn computes_fibonacci_test() {
  let code =
    "let sum = !fix((self, n, a, b, total) -> {
    match !int_compare(n, 0) {
      Eq(_) -> { total }
      | (_) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(total, a)) }
    }
  })
  sum(20, 1, 1, 0)"
  assert Ok(Nil) == pure.check(code, value.Integer(17_710))
}

pub fn rejects_wrong_value_test() {
  let assert Error(_) = pure.check("10945", value.Integer(17_710))
  let assert Error(_) = pure.check("\"17710\"", value.Integer(17_710))
}

pub fn rejects_effect_before_execution_test() {
  let assert Error(reason) =
    pure.evaluate("let _ = perform Print(\"hello\") 17710")
  assert string.contains(reason, "Print")
  let assert Error(_) = pure.evaluate("perform MadeUp({})")
}

pub fn rejects_invalid_programs_test() {
  let assert Error(_) = pure.evaluate("let =")
  let assert Error(_) = pure.evaluate("!int_add(1, \"two\")")
  let assert Error(_) = pure.evaluate("@standard")
}

pub fn context_is_in_scope_test() {
  assert Ok(value.unit()) == pure.evaluate("context")
}

pub fn a_prose_answer_does_not_pass_test() {
  let assert Error(_) = pure.program(chat.Completion("", "17710", []))
}

pub fn run_requires_exactly_one_call_with_string_code_test() {
  let call =
    tool.Call(
      "run",
      tool.FunctionCall("run", dict.from_list([#("code", utils.String("42"))])),
    )
  assert pure.program(chat.Completion("", "", [call])) == Ok("42")
  let assert Error(_) = pure.program(chat.Completion("", "", [call, call]))
  let invalid =
    tool.Call(
      "run",
      tool.FunctionCall("run", dict.from_list([#("code", utils.Integer(42))])),
    )
  let assert Error(_) = pure.program(chat.Completion("", "", [invalid]))
}

pub fn the_model_request_does_not_reveal_the_expected_answer_test() {
  let assert Ok(#(_, request)) = pure.request("openai-local:fixture", "../..")
  let assert Ok(body) = bit_array.to_string(request.body)
  assert !string.contains(body, "17710")
  assert string.contains(body, "first 20 Fibonacci")
  assert string.contains(body, "\"name\":\"run\"")
}

pub fn divergent_programs_exhaust_the_interpreter_budget_test() {
  let assert Error(reason) =
    pure.evaluate("let spin = !fix((self, n) -> { self(n) }) spin(1)")
  assert string.contains(reason, "ExecutionLimit")
}
