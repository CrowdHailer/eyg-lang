import cloud/agent
import gleam/dict
import gleam/erlang/process
import gleam/list
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool

fn run_call(code) {
  tool.Call(
    id: "call-1",
    function: tool.FunctionCall(
      name: "run",
      arguments: dict.from_list([#("code", utils.String(code))]),
    ),
  )
}

/// A model that replies with each completion in turn.
fn scripted(completions) {
  let subject = process.new_subject()
  list.each(completions, process.send(subject, _))
  fn(_history) {
    case process.receive(subject, 0) {
      Ok(completion) -> Ok(completion)
      Error(Nil) -> Error("script finished")
    }
  }
}

pub fn runs_code_until_the_agent_stops_test() {
  let complete =
    scripted([
      chat.Completion("", "", [run_call("perform Post(\"hi\")")]),
      chat.Completion("", "Posted a greeting.", []),
    ])
  let ran = process.new_subject()
  let run_code = fn(code) {
    process.send(ran, code)
    Ok("Result:\nOk(\"m1\")")
  }
  let assert Ok(history) =
    agent.turn([], "[#general] alice: hello", complete, run_code)
  assert process.receive(ran, 0) == Ok("perform Post(\"hi\")")
  assert agent.last_reply(history) == "Posted a greeting."
  let assert [
    _reply,
    chat.ToolResultMessage(text:, ..),
    _call,
    chat.UserMessage(..),
  ] = history
  assert text == "Result:\nOk(\"m1\")"
}

pub fn failed_completion_is_an_error_test() {
  let complete = fn(_history) { Error("offline") }
  let run_code = fn(_code) { Ok("") }
  assert agent.turn([], "hello", complete, run_code) == Error("offline")
}

pub fn unknown_tool_is_reported_to_the_agent_test() {
  let call =
    tool.Call(id: "x", function: tool.FunctionCall("shell", dict.new()))
  let complete =
    scripted([chat.Completion("", "", [call]), chat.Completion("", "ok", [])])
  let assert Ok([_, chat.ToolResultMessage(text:, ..), ..]) =
    agent.turn([], "hello", complete, fn(_) { Ok("") })
  assert text == "Failed to call tool `shell` it is not setup."
}
