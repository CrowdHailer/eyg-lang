import cloud/invocation

pub fn fenced_eyg_is_an_invocation_test() {
  assert invocation.parse("```eyg\n!int_add(1, 2)\n```") == Ok("!int_add(1, 2)")
}

pub fn surrounding_whitespace_test() {
  assert invocation.parse("  ```eyg\nx\n```\n") == Ok("x")
}

pub fn plain_text_is_for_the_agent_test() {
  assert invocation.parse("what is 1 + 2?") == Error(Nil)
}

pub fn other_languages_are_for_the_agent_test() {
  assert invocation.parse("```js\n1 + 2\n```") == Error(Nil)
}

pub fn text_around_code_is_for_the_agent_test() {
  assert invocation.parse("run this ```eyg\nx\n```") == Error(Nil)
  assert invocation.parse("```eyg\nx\n``` and ```eyg\ny\n```") == Error(Nil)
}
