//// The page: the board on the right and, on the left, a console that is
//// either an EYG shell or a conversation with an agent. Both change the board
//// the same way, by running EYG. Pressing on the board does nothing.

import eyg/embed/agent.{type Agent}
import eyg/embed/browser
import eyg/embed/shell.{type Shell}
import frontend/hashi_grid
import gleam/dynamic/decode
import gleam/http/request
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import hashi/board.{type Board}
import hashi/play
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/mistral
import overlay/llm/provider/ollama

pub type Flags {
  Flags(library: String, guide: String, seed: Int, origin: String)
}

pub type Mode {
  Shell
  Chat
}

pub type Author {
  Person
  Model
}

pub type Entry {
  Ran(by: Author, code: String, output: String, ok: Bool)
  Said(by: Author, text: String)
  Problem(text: String)
}

pub type Settings {
  Settings(service: String, address: String, model: String, key: String)
}

pub type State {
  State(
    board: Board,
    shell: Shell,
    agent: Agent,
    system: String,
    mode: Mode,
    code: String,
    prompt: String,
    thinking: Bool,
    transcript: List(Entry),
    settings: Settings,
  )
}

pub type Message {
  UserEditedCode(String)
  UserRanCode
  UserEditedPrompt(String)
  UserSentPrompt
  UserSwitched(Mode)
  UserChangedSettings(Settings)
  UserAskedForNewBoard
  ModelResponded(Result(BitArray, String))
  BoardProducedMessage
}

pub fn init(flags: Flags) -> #(State, Effect(Message)) {
  let Flags(library:, guide:, seed:, origin:) = flags
  let assert Ok(shell) = play.start(library)
  let system =
    agent.system_prompt(purpose, shell.text(shell, "hashi", "readme"), guide)
  let settings =
    Settings(service: "ollama", address: origin, model: "qwen3", key: "")
  let state =
    State(
      board: board.generate(seed),
      shell:,
      agent: agent.new(llm(settings), system),
      system:,
      mode: Shell,
      code: "hashi.unfinished({})",
      prompt: "",
      thinking: False,
      transcript: [],
      settings:,
    )
  #(state, effect.none())
}

fn llm(settings: Settings) {
  let Settings(service:, address:, model:, key:) = settings
  let provider = case service {
    "mistral" -> provider.Mistral(mistral.Config(api_key: key))
    _ -> {
      let origin =
        origin.from_string(address) |> result_or(ollama.local().origin)
      let api_key = case key {
        "" -> None
        key -> Some(key)
      }
      provider.Ollama(ollama.Config(origin:, api_key:))
    }
  }
  provider.Llm(provider:, model:)
}

fn result_or(result, default) {
  case result {
    Ok(value) -> value
    Error(_) -> default
  }
}

pub fn update(state: State, message: Message) -> #(State, Effect(Message)) {
  case message {
    UserEditedCode(code) -> #(State(..state, code:), effect.none())
    UserRanCode -> {
      let result = play.run(state.shell, state.board, state.code)
      let play.Run(shell:, board:, outcome:, ..) = result
      let code = case outcome {
        shell.Returned(_) -> ""
        _ -> state.code
      }
      let transcript = [ran(Person, state.code, result), ..state.transcript]
      #(State(..state, shell:, board:, code:, transcript:), effect.none())
    }
    UserEditedPrompt(prompt) -> #(State(..state, prompt:), effect.none())
    UserSentPrompt ->
      case state.thinking, string.trim(state.prompt) {
        True, _ | _, "" -> #(state, effect.none())
        False, text -> {
          let #(agent, request) = agent.ask(state.agent, text)
          let transcript = [Said(Person, text), ..state.transcript]
          let state =
            State(..state, agent:, prompt: "", thinking: True, transcript:)
          #(state, send(request))
        }
      }
    UserSwitched(mode) -> #(State(..state, mode:), effect.none())
    UserChangedSettings(settings) -> {
      let agent = agent.new(llm(settings), state.system)
      #(State(..state, settings:, agent:), effect.none())
    }
    UserAskedForNewBoard -> {
      let board = board.generate(int.random(1_000_000))
      #(State(..state, board:), effect.none())
    }
    ModelResponded(Error(reason)) -> {
      let transcript = [Problem(reason), ..state.transcript]
      #(State(..state, thinking: False, transcript:), effect.none())
    }
    ModelResponded(Ok(body)) -> {
      let workspace = #(state.shell, state.board, state.transcript)
      case agent.respond(state.agent, workspace, body, run_for_agent) {
        agent.Continue(agent:, state: #(shell, board, transcript), request:, ..) -> {
          let state = State(..state, agent:, shell:, board:, transcript:)
          #(state, send(request))
        }
        agent.Answered(agent:, state: #(shell, board, transcript), text:) -> {
          let transcript = [Said(Model, text), ..transcript]
          let state =
            State(..state, agent:, shell:, board:, transcript:, thinking: False)
          #(state, effect.none())
        }
        agent.Failed(agent:, reason:, ..) -> {
          let transcript = [Problem(reason), ..state.transcript]
          #(State(..state, agent:, thinking: False, transcript:), effect.none())
        }
      }
    }
    BoardProducedMessage -> #(state, effect.none())
  }
}

const purpose =
  "You play a puzzle game for the user by writing EYG programs and running them with the run tool."

// The agent's runs go to the same shell and board, and into the transcript.
fn run_for_agent(workspace, code) {
  let #(shell, board, transcript) = workspace
  let result = play.run(shell, board, code)
  let transcript = [ran(Model, code, result), ..transcript]
  #(#(result.shell, result.board, transcript), play.report(result))
}

fn ran(by, code, result: play.Run) {
  let ok = case result.outcome {
    shell.Returned(_) -> True
    _ -> False
  }
  Ran(by:, code:, output: play.report(result), ok:)
}

fn send(request: request.Request(BitArray)) -> Effect(Message) {
  use dispatch <- effect.from
  promise.tap(browser.send(request), fn(response) {
    dispatch(
      ModelResponded(case response {
        Ok(response) if response.status == 200 -> Ok(response.body)
        Ok(response) ->
          Error("model answered " <> int.to_string(response.status))
        Error(reason) -> Error(browser.describe(reason))
      }),
    )
  })
  Nil
}

pub fn view(state: State) -> Element(Message) {
  h.div([a.class("page")], [
    h.section([a.class("console")], [
      h.header([a.class("tabs")], [
        tab(state, Shell, "Shell"),
        tab(state, Chat, "Agent"),
      ]),
      h.ol([a.class("transcript")], list.map(state.transcript, entry)),
      case state.mode {
        Shell -> shell_input(state)
        Chat -> chat_input(state)
      },
    ]),
    h.main([a.class("game center stack")], [
      h.h1([], [h.text("Hashi")]),
      hashi_grid.view(state.board.grid)
        |> element.map(fn(_) { BoardProducedMessage }),
      case board.is_solved(state.board) {
        True -> h.p([a.class("solved")], [h.text("Solved!")])
        False -> h.p([], [h.text("Solve it by running EYG")])
      },
      h.button([event.on_click(UserAskedForNewBoard)], [h.text("New puzzle")]),
    ]),
  ])
}

fn tab(state: State, mode, label) {
  h.button(
    [
      a.class("tab"),
      a.aria_pressed(case state.mode == mode {
        True -> "true"
        False -> "false"
      }),
      event.on_click(UserSwitched(mode)),
    ],
    [h.text(label)],
  )
}

fn entry(entry: Entry) {
  case entry {
    Ran(by:, code:, output:, ok:) ->
      h.li(
        [
          a.class("run"),
          a.classes([#("failed", !ok), #("by-model", by == Model)]),
        ],
        [
          case code {
            "" -> element.none()
            code -> h.pre([a.class("code")], [h.text(code)])
          },
          h.pre([a.class("output")], [h.text(output)]),
        ],
      )
    Said(by:, text:) ->
      h.li([a.class("said"), a.classes([#("by-model", by == Model)])], [
        h.text(text),
      ])
    Problem(text:) -> h.li([a.class("problem")], [h.text(text)])
  }
}

fn shell_input(state: State) {
  h.form([a.class("input"), event.on_submit(fn(_) { UserRanCode })], [
    h.textarea(
      [
        a.class("code"),
        a.attribute("aria-label", "EYG code"),
        a.attribute("spellcheck", "false"),
        a.rows(6),
        event.on_input(UserEditedCode),
        on_ctrl_enter(UserRanCode),
      ],
      state.code,
    ),
    h.button([a.type_("submit")], [h.text("Run")]),
  ])
}

fn chat_input(state: State) {
  let Settings(service:, address:, model:, key:) = state.settings
  let set = fn(settings) { UserChangedSettings(settings) }
  h.div([a.class("input")], [
    h.div([a.class("settings")], [
      h.select(
        [
          a.attribute("aria-label", "Provider"),
          event.on_change(fn(service) {
            set(Settings(..state.settings, service:))
          }),
        ],
        [
          h.option(
            [a.value("ollama"), a.selected(service == "ollama")],
            "Ollama",
          ),
          h.option(
            [a.value("mistral"), a.selected(service == "mistral")],
            "Mistral",
          ),
        ],
      ),
      h.input([
        a.attribute("aria-label", "Address"),
        a.value(address),
        a.disabled(service == "mistral"),
        event.on_change(fn(address) {
          set(Settings(..state.settings, address:))
        }),
      ]),
      h.input([
        a.attribute("aria-label", "Model"),
        a.value(model),
        event.on_change(fn(model) { set(Settings(..state.settings, model:)) }),
      ]),
      h.input([
        a.attribute("aria-label", "API key"),
        a.type_("password"),
        a.placeholder("API key"),
        a.value(key),
        event.on_change(fn(key) { set(Settings(..state.settings, key:)) }),
      ]),
    ]),
    h.form([a.class("prompt"), event.on_submit(fn(_) { UserSentPrompt })], [
      h.textarea(
        [
          a.attribute("aria-label", "Message"),
          a.placeholder("Ask the agent to play"),
          a.rows(3),
          event.on_input(UserEditedPrompt),
          on_ctrl_enter(UserSentPrompt),
        ],
        state.prompt,
      ),
      h.button([a.type_("submit"), a.disabled(state.thinking)], [
        h.text(case state.thinking {
          True -> "Thinking"
          False -> "Send"
        }),
      ]),
    ]),
  ])
}

fn on_ctrl_enter(message) {
  event.advanced("keydown", {
    use key <- decode.field("key", decode.string)
    use ctrl <- decode.field("ctrlKey", decode.bool)
    use meta <- decode.field("metaKey", decode.bool)
    case key, ctrl || meta {
      "Enter", True ->
        decode.success(event.handler(
          message,
          prevent_default: True,
          stop_propagation: False,
        ))
      _, _ -> decode.failure(event.handler(message, False, False), "ctrl enter")
    }
  })
}
