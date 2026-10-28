import etui/backend
import eyg/cli/args
import eyg/cli/helpers
import eyg/cli/internal/terminal as interrupt
import eyg/cli/overlay as cli
import eyg/cli/tui/overlay
import eyg/cli/tui/terminal
import glasshouse/session as trace
import gleam/dict
import gleam/string
import loam/sandbox
import loam/source
import overlay/llm/chat
import overlay/llm/tool
import overlay/policy
import touch_grass/harness/computer
import touch_grass/interface

fn prepared() {
  let code =
    "{llm: {provider: Ollama({origin: \"https://fixture.test\", api_key: None({})}), model: \"fixture\"}, policy: {now: (x) -> { Pass(x) }}, context: {}}"
  let assert #(sandbox.Returned(#(Ok(session), execution)), _) =
    cli.setup(
      source.Code(code),
      helpers.config,
      computer.effects() |> interface.take(["Now"]),
      [#("Now", policy.PolicyField("now"))],
      helpers.state(),
    )
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_now(100))
  overlay.Agent(session, execution, [], cli.start_trace("fixture", session))
  |> overlay.init
}

pub fn overlay_command_is_distinct_from_structural_shell_test() {
  assert args.parse(["tui", "overlay", "agent.eyg"])
    == args.TuiOverlay(source.File("agent.eyg"))
}

pub fn busy_turn_retains_streamed_text_and_prevents_another_submission_test() {
  let send = fn(_) { Nil }
  let state = prepared()
  let assert #(state, []) =
    overlay.update(state, terminal.Input(backend.Paste("Compute 42")), send)
  let assert #(state, [_]) =
    overlay.update(state, terminal.Input(backend.KeyPress("enter")), send)
  assert state.busy
  let assert #(state, []) =
    overlay.update(state, terminal.Task(overlay.Chunk("Computed ")), send)
  let assert #(state, []) =
    overlay.update(state, terminal.Task(overlay.Chunk("42.")), send)
  let assert [overlay.Row("Assistant", "Computed 42.", False), ..] = state.rows
  let assert #(state, []) =
    overlay.update(state, terminal.Input(backend.KeyPress("enter")), send)
  let assert #(state, []) =
    overlay.update(state, terminal.Input(backend.KeyPress("ctrl+c")), send)
  assert interrupt.interrupted(state.agent.session.interrupt)
  interrupt.end_turn(state.agent.session.interrupt)
}

pub fn details_and_prompt_exit_do_not_run_effects_test() {
  let state = prepared()
  let assert #(state, []) =
    overlay.update(state, terminal.Input(backend.KeyPress("ctrl+o")), fn(_) {
      Nil
    })
  assert state.expanded
  let assert #(state, []) =
    overlay.update(state, terminal.Input(backend.KeyPress("ctrl+c")), fn(_) {
      Nil
    })
  assert state.quit
}

pub fn terminal_control_bytes_cannot_escape_the_transcript_test() {
  assert overlay.clean("hello\u{1b}[2J\u{0}world\nnext")
    == "hello[2Jworld\nnext"
}

pub fn stopping_before_a_tool_records_a_reply_for_the_next_turn_test() {
  let state = prepared()
  let call = tool.Call("native-call", tool.FunctionCall("run", dict.new()))
  let agent =
    overlay.Agent(
      ..state.agent,
      trace: cli.Trace(..state.agent.trace, generations: 1),
    )
  let state = overlay.State(..state, agent:, busy: True)
  interrupt.request_stop(agent.session.interrupt)
  let assert #(_, [work]) =
    overlay.update(
      state,
      terminal.Task(overlay.Generated(Ok([call]), agent)),
      fn(_) { Nil },
    )
  let assert #(sandbox.Returned(overlay.Saved(_, agent)), _) =
    sandbox.run(work, sandbox.sandbox() |> sandbox.with_now(200))
  let assert [chat.ToolResultMessage("native-call", text, _)] = agent.history
  assert string.contains(text, "Stopped before")
  let assert [trace.ToolResult(call_id: "g1/1", ..), ..] = agent.trace.events
}
