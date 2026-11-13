import glasshouse/context.{Assistant, System, Tool, User}
import glasshouse/fixtures
import glasshouse/session
import glasshouse/usage
import gleam/option.{Some}

pub fn context_before_first_prompt_is_the_system_prompt_test() {
  let #(session, _) = fixtures.session()
  let assert Some(agent) = session.agent
  assert context.before(session, 1) == [System(agent.system_prompt)]
}

pub fn context_grows_with_the_conversation_test() {
  let #(session, _) = fixtures.session()
  let assert Some(agent) = session.agent
  assert context.before(session, 5)
    == [
      System(agent.system_prompt),
      User("number the second line"),
      Assistant("", "", [session.ToolCall("g1/0", "run", "{\"code\":\"...\"}")]),
      Tool("g1/0", "done"),
    ]
}

pub fn failed_generations_discard_the_prompt_test() {
  let #(session, _) = fixtures.session()
  let assert [config, prompt, session.Generated(generation), ..] =
    session.events
  let failed =
    session.Generated(
      session.Generation(..generation, error: Some("unauthorized")),
    )
  let session =
    session.Session(..session, events: [
      config,
      prompt,
      failed,
      session.Prompt(at: 0, text: "again"),
    ])
  let assert Some(agent) = session.agent
  assert context.before(session, 4)
    == [System(agent.system_prompt), User("again")]
}

pub fn messages_from_ollama_request_test() {
  let body = <<
    "{\"model\":\"m\",\"messages\":[{\"role\":\"system\",\"content\":\"be brief\"},{\"role\":\"user\",\"content\":\"hi\"},{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"function\":{\"name\":\"run\",\"arguments\":{\"code\":\"1\"}}}]},{\"role\":\"tool\",\"content\":\"1\"}],\"stream\":false}":utf8,
  >>
  assert context.from_request(body)
    == Ok([
      System("be brief"),
      User("hi"),
      Assistant("", "", [session.ToolCall("", "run", "{\"code\":\"1\"}")]),
      Tool("", "1"),
    ])
}

pub fn messages_from_mistral_request_test() {
  let body = <<
    "{\"messages\":[{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"function\":{\"name\":\"run\",\"arguments\":\"{\\\"code\\\":\\\"1\\\"}\"}}]},{\"role\":\"tool\",\"tool_call_id\":\"c1\",\"content\":\"1\"}]}":utf8,
  >>
  assert context.from_request(body)
    == Ok([
      Assistant("", "", [session.ToolCall("c1", "run", "{\"code\":\"1\"}")]),
      Tool("c1", "1"),
    ])
}

pub fn ollama_usage_test() {
  let body = <<
    "{\"message\":{\"content\":\"hi\"},\"prompt_eval_count\":26,\"eval_count\":290}":utf8,
  >>
  assert usage.from_response(body) == session.Usage(26, 290)
}

pub fn mistral_usage_test() {
  let body = <<
    "{\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}":utf8,
  >>
  assert usage.from_response(body) == session.Usage(10, 5)
}

pub fn streamed_usage_takes_the_final_report_test() {
  let body = <<
    "{\"message\":{\"content\":\"h\"},\"done\":false}\n{\"message\":{\"content\":\"i\"},\"done\":true,\"prompt_eval_count\":7,\"eval_count\":2}\n":utf8,
  >>
  assert usage.from_response(body) == session.Usage(7, 2)
  let sse = <<
    "data: {\"choices\":[]}\n\ndata: {\"choices\":[],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":4}}\n\ndata: [DONE]\n":utf8,
  >>
  assert usage.from_response(sse) == session.Usage(3, 4)
}

pub fn missing_usage_is_zero_test() {
  assert usage.from_response(<<"{}">>) == session.no_usage()
  assert usage.from_response(<<255>>) == session.no_usage()
}

pub fn estimate_test() {
  assert usage.estimate("") == 0
  assert usage.estimate("abcd") == 1
  assert usage.estimate("abcde") == 2
}
