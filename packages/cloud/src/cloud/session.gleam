//// One session per conversation, it holds the agent's history.
////
//// Inputs are queued while a turn runs and given to the agent together in the next turn.
//// Observations are added to the next turn without starting one.
////
//// Each turn prepares the channel shell in its own process,
//// so configuration changes apply from the next turn.
//// EYG values are never sent between processes, see `notes/cloud-process-boundaries.md`.

import cloud/agent
import cloud/beam/execute
import cloud/config
import cloud/shell
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import overlay/llm/chat

pub type Message {
  /// Something the agent should respond to, starts a turn.
  Input(text: String)
  /// Context for the agent's next turn, it does not start a turn.
  Observe(text: String)
  /// Forget the conversation so far, the next input starts a new one.
  Reset
  TurnFinished(epoch: Int, input: String, result: Result(agent.History, String))
}

/// The most messages kept in a session's history.
pub const max_history = 200

/// Everything about a session that is fixed when it starts.
pub type Setup {
  Setup(
    /// The conversation key, used in logs.
    name: String,
    channel: config.ChannelInfo,
    /// Where the agent is, given to the agent with the workspace and channel readmes.
    location: String,
    load: config.Loader,
    complete: agent.Completer,
    host: execute.Host,
  )
}

type State {
  State(
    setup: Setup,
    self: Subject(Message),
    history: agent.History,
    busy: Bool,
    /// Inputs and observations for the next turn, newest first.
    queue: List(String),
    /// True if the queue holds an input, so a turn should start.
    waiting: Bool,
    /// Increased on reset, turns started before a reset are discarded.
    epoch: Int,
  )
}

pub fn start(setup: Setup) -> Result(Subject(Message), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    State(
      setup:,
      self:,
      history: [],
      busy: False,
      queue: [],
      waiting: False,
      epoch: 0,
    )
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Input(text) ->
      State(..state, queue: [text, ..state.queue], waiting: True) |> next
    Observe(text) ->
      State(..state, queue: [text, ..state.queue]) |> actor.continue
    Reset ->
      State(
        ..state,
        history: [],
        queue: [],
        waiting: False,
        epoch: state.epoch + 1,
      )
      |> actor.continue
    TurnFinished(epoch:, ..) if epoch != state.epoch ->
      State(..state, busy: False) |> next
    TurnFinished(input:, result:, ..) -> {
      let history = case result {
        Ok(history) -> {
          io.println(
            state.setup.name <> " agent: " <> agent.last_reply(history),
          )
          history
        }
        Error(reason) -> {
          io.println_error(state.setup.name <> " turn failed: " <> reason)
          // Keep the input so the next turn still sees it.
          [chat.UserMessage(input, []), ..state.history]
        }
      }
      let history = agent.trim(history, max_history)
      State(..state, history:, busy: False) |> next
    }
  }
}

/// Start a turn with every queued input, if the agent is not already busy.
fn next(state: State) {
  case state.busy, state.waiting {
    True, _ | False, False -> actor.continue(state)
    False, True -> {
      let text = state.queue |> list.reverse |> string.join("\n\n")
      let State(setup:, self:, history:, epoch:, ..) = state
      process.spawn(fn() {
        let result = turn(setup, history, text)
        process.send(self, TurnFinished(epoch, text, result))
      })
      actor.continue(State(..state, busy: True, queue: [], waiting: False))
    }
  }
}

fn turn(setup: Setup, history, text) {
  use shell <- result.try(shell.prepare(
    setup.load,
    setup.channel,
    setup.host,
    setup.location,
    setup.complete,
  ))
  shell.turn(shell, history, text)
}
