import glasshouse/archive
import glasshouse/rerun
import glasshouse/run
import glasshouse/session
import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import oas/generator/utils
import overlay/helpers.{new_reader, submit_first_prompt}
import overlay/llm/chat
import overlay/llm/tool
import overlay/web/state.{type State, State}
import overlay/web/trace
import overlay/web/view
import pal/system

fn call(id, code) {
  tool.Call(
    id:,
    function: tool.FunctionCall(
      name: "run",
      arguments: dict.from_list([#("code", utils.String(code))]),
    ),
  )
}

// The model streams a reply with one tool call, the program runs to completion.
fn completes(state: State, code) {
  let completion =
    chat.Completion(thinking: "", content: "", tool_calls: [call("", code)])
  let status =
    state.Streaming(
      reader: new_reader([], Ok(Nil)),
      completion:,
      remaining: <<>>,
    )
  let state = State(..state, status:, streamed: <<"{\"done\":true}">>)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert [system.FetchStreamResponse(..), ..] = actions
  state
}

fn run_kind(outcome) {
  case outcome {
    run.Returned(..) -> "returned"
    run.Rejected(..) -> "rejected"
    _ -> "other"
  }
}

fn session_of(state: State) {
  trace.session(state.trace, state.agent(state), 1000)
}

pub fn a_session_is_recorded_test() {
  let #(state, _) = submit_first_prompt("add numbers")
  let state = completes(state, "let _ = perform Random(10) !int_add(2, 3)")
  let assert [
    session.Execution(config),
    session.Prompt(text: "add numbers", ..),
    session.Generated(generation),
    session.Execution(tool),
    session.ToolResult(call_id: "g1/0", text: "5", ..),
  ] = session_of(state).events
  assert config.kind == run.Config
  assert generation.id == "g1"
  let assert [session.ToolCall(id: "g1/0", name: "run", ..)] =
    generation.tool_calls
  assert tool.kind == run.Tool("g1/0")
  assert list.map(tool.journal, fn(entry) { entry.label }) == ["Random"]
}

pub fn recorded_sessions_replay_test() {
  let #(state, _) = submit_first_prompt("add numbers")
  // This program does not type check so it never runs.
  let state = completes(state, "!int_add(1, \"x\")")
  let state =
    completes(
      state,
      "let _ = perform Random(10) !string_append(context.readme, \"!\")",
    )
  let archive = trace.archive(state.trace, state.agent(state), 1000)
  let assert Ok(archive) = archive.from_string(archive.to_string(archive))
  let reports = rerun.session(archive.session, archive.store)
  assert list.map(reports, fn(r) { r.run.outcome |> run_kind })
    == ["returned", "rejected", "returned"]
  assert list.all(reports, fn(r) { r.problem == None })
}

pub fn the_agent_can_read_the_trace_test() {
  let #(state, _) = submit_first_prompt("add numbers")
  let state = completes(state, "let _ = perform Random(10) !int_add(2, 3)")
  let state = completes(state, "perform Trace({})")
  let assert Ok(session.ToolResult(text:, ..)) =
    session_of(state).events |> list.last
  assert string.contains(text, "call: \"g1/0\"")
  assert string.contains(text, "label: \"Random\"")
  assert string.contains(text, "result: \"5\"")
}

pub fn traces_can_be_downloaded_test() {
  let #(state, _) = submit_first_prompt("add numbers")
  let state = completes(state, "!int_add(2, 3)")
  let #(_, actions) = state.update(state, state.UserClickedDownloadTrace)
  let assert [system.Download(input, _)] = actions
  assert string.ends_with(input.name, "-web.json")
  let assert Ok(text) = bit_array.to_string(input.content)
  let assert Ok(archive) = archive.from_string(text)
  assert archive.session.id <> ".json" == input.name
}

pub fn ids_are_the_start_time_test() {
  assert trace.new_id(1_791_889_260_123) == "20261013T110100-web"
}

pub fn sessions_started_together_have_independent_ids_test() {
  let a = trace.new_session(1000)
  let b = trace.new_session(1000)
  assert a.id != b.id
}

pub fn stopping_a_model_request_records_its_failure_test() {
  let #(state, _) = submit_first_prompt("add numbers")
  let #(state, _) = state.update(state, state.UserClickedStop)
  let assert [_, _, session.Generated(generation)] = session_of(state).events
  assert generation.error == Some("Stopped.")
  assert state.asked == None
}

pub fn programs_are_pinned_test() {
  let #(state, _) = submit_first_prompt("add numbers")
  let state = completes(state, "!int_add(2, 3)")
  let assert [_, _, _, session.Execution(tool), _] = session_of(state).events
  let assert Some(_) = tool.program
}

pub fn the_trace_is_shown_test() {
  let #(state, _) = submit_first_prompt("add numbers")
  let code = "let _ = perform Random(10) !int_add(2, 3)"
  let state = completes(state, code)
  let #(id, runs) = view.trace(state)
  assert id == state.trace.id
  assert runs == [view.Run("g1/0", code, [#("Random", "10")], "5")]
}
