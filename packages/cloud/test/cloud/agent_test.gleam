import cloud/beam/execute
import cloud/overlay as agent
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
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

pub fn agent_can_run_beyond_the_former_sixteen_round_limit_test() {
  let complete =
    scripted(
      list.append(list.repeat(chat.Completion("", "", [run_call("work")]), 20), [
        chat.Completion("", "done", []),
      ]),
    )
  let #(history, calls, error) =
    agent.complete_loop(
      [],
      complete,
      fn(_, count) { #(Ok("ok"), count + 1) },
      fn(_) { Nil },
      0,
    )
  assert calls == 20
  assert error == None
  assert agent.last_reply(history) == "done"
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
  let #(history, _, _) =
    agent.complete_loop(
      [chat.UserMessage("[#general] alice: hello", [])],
      complete,
      fn(code, state) { #(run_code(code), state) },
      fn(_) { Nil },
      Nil,
    )
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
  let #(_, _, error) =
    agent.complete_loop(
      [],
      complete,
      fn(code, state) { #(run_code(code), state) },
      fn(_) { Nil },
      Nil,
    )
  assert error == Some("offline")
}

pub fn unknown_tool_is_reported_to_the_agent_test() {
  let call =
    tool.Call(id: "x", function: tool.FunctionCall("shell", dict.new()))
  let complete =
    scripted([chat.Completion("", "", [call]), chat.Completion("", "ok", [])])
  let assert #([_, chat.ToolResultMessage(text:, ..), ..], _, _) =
    agent.complete_loop(
      [],
      complete,
      fn(_, state) { #(Ok(""), state) },
      fn(_) { Nil },
      Nil,
    )
  assert text == "Failed to call tool `shell` it is not setup."
}

pub fn trim_keeps_whole_turns_test() {
  let history = [
    chat.AssistantMessage("", "done", []),
    chat.ToolResultMessage("c", "ok", []),
    chat.AssistantMessage("", "", [run_call("x")]),
    chat.UserMessage("second", []),
    chat.AssistantMessage("", "first done", []),
    chat.UserMessage("first", []),
  ]
  assert agent.trim(history, 10) == history
  assert agent.trim(history, 5) == list.take(history, 4)
  assert agent.trim(history, 3) == []
}

pub fn completed_tools_and_state_survive_a_later_provider_failure_test() {
  let complete =
    scripted([chat.Completion("", "working", [run_call("change")])])
  let emitted = process.new_subject()
  let #(history, state, error) =
    agent.complete_loop(
      [chat.UserMessage("start", [])],
      complete,
      fn(_, state) { #(Ok("saved"), state + 1) },
      process.send(emitted, _),
      0,
    )
  assert state == 1
  assert error == Some("script finished")
  let assert [
    chat.ToolResultMessage(text: "saved", ..),
    chat.AssistantMessage(..),
    chat.UserMessage(..),
  ] = history
  assert process.receive(emitted, 0) == Ok(execute.StandardOut("working"))
  assert process.receive(emitted, 0)
    == Ok(execute.StandardError("script finished"))
}
