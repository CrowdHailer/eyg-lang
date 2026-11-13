//// A recorded agent frontend using the structural shell's terminal lifecycle.

import etui/backend
import etui/buffer
import etui/geometry
import etui/span
import etui/widgets/input
import etui/widgets/paragraph
import eyg/cli/etui/widgets/combobox
import eyg/cli/internal/config
import eyg/cli/internal/terminal as interrupt
import eyg/cli/internal/traces
import eyg/cli/overlay as cli
import eyg/cli/tui/terminal
import glasshouse/session as trace
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import javascript/mutable_reference as ref
import loam/execute
import loam/system
import oas/generator/utils
import overlay/agent
import overlay/llm/chat
import overlay/llm/tool
import touch_grass/harness/computer

pub type Agent {
  Agent(
    session: cli.Session(computer.Effect),
    execution: execute.State,
    history: List(chat.Message(tool.Call)),
    trace: cli.Trace,
  )
}

pub type Row {
  Row(label: String, text: String, detail: Bool)
}

pub type State {
  State(
    agent: Agent,
    editing: input.InputState,
    rows: List(Row),
    pending: List(tool.Call),
    index: Int,
    busy: Bool,
    expanded: Bool,
    quit: Bool,
  )
}

pub type Message {
  Chunk(String)
  Observed(String, String, String, String)
  Generated(Result(List(tool.Call), String), Agent)
  Called(Result(tool.Return, String), tool.Call, Agent)
  Saved(Result(String, String), Agent)
}

pub fn init(agent: Agent) {
  State(
    agent:,
    editing: input.state_new(),
    rows: [],
    pending: [],
    index: 0,
    busy: False,
    expanded: False,
    quit: False,
  )
}

pub fn execute(source, config: config.Config) {
  use started <- promise.try_await(system.run(cli.initialize(source, config)))
  let #(session, execution) = started
  use id <- promise.await(system.run(traces.new_id(session.config.started)))
  let agent = Agent(session, execution, [], cli.start_trace(id, session))
  let send = ref.new(fn(_: Message) { Nil })
  terminal.run_with(
    init(agent),
    fn(state, event) {
      update(state, event, fn(message) { ref.get(send)(message) })
    },
    render,
    fn(state) { state.quit },
    fn(dispatch) {
      let _ = ref.set(send, fn(message) { dispatch([terminal.Task(message)]) })
      Nil
    },
  )
}

fn row(state: State, label, text, detail) {
  State(..state, rows: [Row(label, text, detail), ..state.rows])
}

fn generate(agent: Agent, send) {
  use #(completion, trace) <- system.map(
    cli.streamed_generation(
      agent.session,
      list.reverse(agent.history),
      agent.trace,
      fn(text) { system.Done(send(Chunk(text))) },
    ),
  )
  case completion {
    Ok(completion) ->
      Generated(
        Ok(completion.tool_calls),
        Agent(..agent, trace:, history: [
          chat.from_completion(completion),
          ..agent.history
        ]),
      )
    Error(reason) -> Generated(Error(reason), Agent(..agent, trace:))
  }
}

fn save(state: State) {
  let _ = interrupt.end_turn(state.agent.session.interrupt)
  let work = {
    use at <- system.then(system.now())
    let agent = state.agent
    let #(history, events, _) =
      list.fold(
        state.pending,
        #(agent.history, agent.trace.events, state.index),
        fn(acc, call) {
          let #(history, events, index) = acc
          let text = "Stopped before this tool call"
          #(
            [cli.result_to_message(call.id, Error(text)), ..history],
            [
              trace.ToolResult(
                at:,
                call_id: cli.call_id(
                  "g" <> int.to_string(agent.trace.generations),
                  index + 1,
                ),
                text:,
              ),
              ..events
            ],
            index + 1,
          )
        },
      )
    let agent =
      Agent(..agent, history:, trace: cli.Trace(..agent.trace, events:))
    use saved <- system.map(cli.save(agent.session, agent.trace))
    Saved(saved, agent)
  }
  #(State(..state, pending: []), [work])
}

fn next(state: State, send) {
  case interrupt.interrupted(state.agent.session.interrupt) {
    True -> save(row(state, "Stopped", "Send a message to continue.", False))
    False ->
      case state.pending {
        [] -> #(state, [generate(state.agent, send)])
        [call, ..pending] -> {
          let code = case
            agent.cast_tool_call(call.function.name, call.function.arguments)
          {
            Ok(agent.Run(code)) -> code
            _ -> utils.fields_to_json(call.function.arguments) |> json.to_string
          }
          let state =
            row(
              State(..state, pending:, index: state.index + 1),
              "Code",
              code,
              True,
            )
          let agent = state.agent
          let work =
            cli.call_recorded(
              agent.session,
              call,
              agent.execution,
              agent.trace,
              state.index,
              fn(label, input, decision, output) {
                send(Observed(label, input, decision, output))
              },
            )
            |> system.map(fn(reply) {
              let #(returned, execution, trace) = reply
              Called(
                returned,
                call,
                Agent(..agent, execution:, trace:, history: [
                  cli.result_to_message(call.id, returned),
                  ..agent.history
                ]),
              )
            })
          #(state, [work])
        }
      }
  }
}

pub fn update(state: State, event: terminal.Event(Message), send) {
  case event {
    terminal.Task(Chunk(text)) -> {
      let rows = case state.rows {
        [Row("Assistant", previous, False), ..rest] -> [
          Row("Assistant", previous <> text, False),
          ..rest
        ]
        rows -> [Row("Assistant", text, False), ..rows]
      }
      #(State(..state, rows:), [])
    }
    terminal.Task(Observed(label, input, decision, output)) -> #(
      row(state, label <> " · " <> decision, input <> " → " <> output, True),
      [],
    )
    terminal.Task(Generated(completion, agent)) -> {
      let state = State(..state, agent:)
      case completion {
        Error(reason) -> save(row(state, "Error", reason, False))
        Ok([]) -> save(state)
        Ok(calls) -> next(State(..state, pending: calls, index: 0), send)
      }
    }
    terminal.Task(Called(returned, _, agent)) -> {
      let text = case returned {
        Ok(returned) -> returned.text
        Error(reason) -> reason
      }
      next(row(State(..state, agent:), "Tool", text, True), send)
    }
    terminal.Task(Saved(saved, agent)) -> {
      let text = result.unwrap(saved, "Unable to save trajectory")
      #(row(State(..state, busy: False, agent:), "Trace", text, False), [])
    }
    terminal.Input(backend.KeyPress("ctrl+c")) ->
      case state.busy {
        True -> {
          let _ = interrupt.request_stop(state.agent.session.interrupt)
          #(state, [])
        }
        False -> #(State(..state, quit: True), [])
      }
    terminal.Input(backend.KeyPress("ctrl+o")) -> #(
      State(..state, expanded: !state.expanded),
      [],
    )
    terminal.Input(backend.KeyPress("enter"))
      if !state.busy && state.editing.value != ""
    -> {
      let text = state.editing.value
      let _ = interrupt.start_turn(state.agent.session.interrupt)
      let work = {
        use at <- system.then(system.now())
        let agent = state.agent
        generate(
          Agent(
            ..agent,
            history: [chat.UserMessage(text, []), ..agent.history],
            trace: cli.prompted(agent.trace, text, at),
          ),
          send,
        )
      }
      #(
        row(
          State(..state, busy: True, editing: input.state_new()),
          "You",
          text,
          False,
        ),
        [work],
      )
    }
    terminal.Input(backend.KeyPress(key)) if !state.busy -> #(
      State(
        ..state,
        editing: combobox.edit_input(
          input.input_new("Message"),
          state.editing,
          key,
        ),
      ),
      [],
    )
    terminal.Input(backend.Paste(text)) if !state.busy -> {
      let editing =
        list.fold(
          string.to_graphemes(string.replace(text, "\n", " ")),
          state.editing,
          fn(editing, char) {
            input.insert_char(input.input_new("Message"), editing, char)
          },
        )
      #(State(..state, editing:), [])
    }
    _ -> #(state, [])
  }
}

pub fn render(state: State, screen: geometry.Rect) {
  let rows =
    list.reverse(state.rows)
    |> list.flat_map(fn(row) {
      let text = case row.detail && !state.expanded {
        True -> string.slice(row.text, 0, 100)
        False -> row.text
      }
      string.split(row.label <> ": " <> clean(text), "\n")
      |> list.map(fn(line) { [span.span_plain(line)] })
    })
  let status =
    "Overlay · "
    <> state.agent.session.llm.model
    <> " · Ctrl-O details · Ctrl-C stop/exit"
  let prompt = case state.busy {
    True -> "Working…"
    False -> "> " <> state.editing.value
  }
  let lines =
    list.append(rows, [[span.span_plain(status)], [span.span_plain(prompt)]])
  let lines =
    list.drop(lines, int.max(0, list.length(lines) - screen.size.height))
  buffer.buffer_new(screen)
  |> paragraph.render_styled(screen, list.map(lines, span.line_new))
}

/// Keep control bytes supplied by a model or tool out of terminal rendering.
pub fn clean(text) {
  text
  |> string.to_utf_codepoints
  |> list.filter(fn(point) {
    let code = string.utf_codepoint_to_int(point)
    code == 10
    || { code >= 32 && code != 127 && !{ code >= 128 && code <= 159 } }
  })
  |> string.from_utf_codepoints
}
