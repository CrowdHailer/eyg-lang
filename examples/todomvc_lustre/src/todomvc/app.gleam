//// TodoMVC, with a console beside it. The list works as usual with the mouse
//// and keyboard, and the console changes it by running EYG, typed by a person
//// or written by an agent.

import eyg/embed/agent.{type Agent}
import eyg/embed/browser
import eyg/embed/shell.{type Shell}
import eyg/hub/cache.{type Cache}
import eyg/parser
import gleam/dynamic/decode
import gleam/http/request
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/mistral
import overlay/llm/provider/ollama
import todomvc/run
import todomvc/tasks.{type Task, type Tasks}

pub type Flags {
  Flags(library: String, guide: String, origin: String)
}

pub type Mode {
  Console
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

pub type Filter {
  All
  Active
  Completed
}

pub type State {
  State(
    tasks: Tasks,
    library: String,
    shell: Result(Shell, String),
    agent: Agent,
    guide: String,
    mode: Mode,
    code: String,
    prompt: String,
    thinking: Bool,
    transcript: List(Entry),
    settings: Settings,
    title: String,
    filter: Filter,
    editing: Option(#(Int, String)),
  )
}

pub type Message {
  HubLoaded(Cache(shell.Span))
  UserEditedCode(String)
  UserRanCode
  UserEditedPrompt(String)
  UserSentPrompt
  UserSwitched(Mode)
  UserChangedSettings(Settings)
  ModelResponded(Result(BitArray, String))
  UserEditedTitle(String)
  UserAddedTask
  UserToggledTask(Int, Bool)
  UserToggledAll(Bool)
  UserDeletedTask(Int)
  UserClearedCompleted
  UserChoseFilter(Filter)
  UserStartedEditing(Task)
  UserEditedTask(String)
  UserFinishedEditing
  UserCancelledEditing
}

/// Shown until the packages the library needs have loaded.
const loading = "Loading @standard from the hub"

pub fn init(flags: Flags) -> #(State, Effect(Message)) {
  let Flags(library:, guide:, origin:) = flags
  let settings =
    Settings(service: "ollama", address: origin, model: "qwen3", key: "")
  let state =
    State(
      tasks: tasks.from_titles([
        "Buy milk #shopping",
        "Call the plumber about the boiler",
        "Buy bread #shopping",
        "Write the EYG post #work",
        "Renew passport",
      ]),
      library:,
      shell: Error(loading),
      agent: agent.new(llm(settings), ""),
      guide:,
      mode: Console,
      code: "let {list} = @standard:1:baguqeerahlbgfg7wjjdjguypivmsdcvh3e2vs4lhiafdbbtl3duxfuzv2eja\nlist.map(todos.tagged(\"#shopping\"), (task) -> { task.title })",
      prompt: "",
      thinking: False,
      transcript: [],
      settings:,
      title: "",
      filter: All,
      editing: None,
    )
  #(state, load_hub(library, origin))
}

fn load_hub(library, page) {
  use dispatch <- effect.from
  let assert Ok(source) = parser.all_from_string(library)
  let assert Ok(hub) = origin.from_string(page)
  cache.load(cache.ready(), source, hub, browser.fetch, browser.hash, fn(_) {
    #(0, 0)
  })(promise.resolve)
  |> promise.tap(fn(cache) { dispatch(HubLoaded(cache)) })
  Nil
}

fn llm(settings: Settings) {
  let Settings(service:, address:, model:, key:) = settings
  let provider = case service {
    "mistral" -> provider.Mistral(mistral.Config(api_key: key))
    _ -> {
      let origin = case origin.from_string(address) {
        Ok(origin) -> origin
        Error(_) -> ollama.local().origin
      }
      let api_key = case key {
        "" -> None
        key -> Some(key)
      }
      provider.Ollama(ollama.Config(origin:, api_key:))
    }
  }
  provider.Llm(provider:, model:)
}

pub fn update(state: State, message: Message) -> #(State, Effect(Message)) {
  case message {
    HubLoaded(cache) -> {
      let shell = run.start(state.library, cache)
      let agent = case shell {
        Ok(shell) -> agent.new(llm(state.settings), system(shell, state.guide))
        Error(_) -> state.agent
      }
      #(State(..state, shell:, agent:), effect.none())
    }
    UserEditedCode(code) -> #(State(..state, code:), effect.none())
    UserRanCode ->
      case state.shell {
        Error(_) -> #(state, effect.none())
        Ok(shell) -> {
          let result = run.run(shell, state.tasks, state.code)
          let run.Run(shell:, tasks:, outcome:, ..) = result
          let code = case outcome {
            shell.Returned(_) -> ""
            _ -> state.code
          }
          let transcript = [ran(Person, state.code, result), ..state.transcript]
          let state =
            State(..state, shell: Ok(shell), tasks:, code:, transcript:)
          #(state, effect.none())
        }
      }
    UserEditedPrompt(prompt) -> #(State(..state, prompt:), effect.none())
    UserSentPrompt ->
      case state.shell, state.thinking, string.trim(state.prompt) {
        Ok(_), False, text if text != "" -> {
          let #(agent, request) = agent.ask(state.agent, text)
          let transcript = [Said(Person, text), ..state.transcript]
          let state =
            State(..state, agent:, prompt: "", thinking: True, transcript:)
          #(state, send(request))
        }
        _, _, _ -> #(state, effect.none())
      }
    UserSwitched(mode) -> #(State(..state, mode:), effect.none())
    UserChangedSettings(settings) -> {
      let agent = case state.shell {
        Ok(shell) -> agent.new(llm(settings), system(shell, state.guide))
        Error(_) -> state.agent
      }
      #(State(..state, settings:, agent:), effect.none())
    }
    ModelResponded(Error(reason)) -> {
      let transcript = [Problem(reason), ..state.transcript]
      #(State(..state, thinking: False, transcript:), effect.none())
    }
    ModelResponded(Ok(body)) ->
      case state.shell {
        Error(_) -> #(state, effect.none())
        Ok(shell) -> responded(state, shell, body)
      }
    UserEditedTitle(title) -> #(State(..state, title:), effect.none())
    UserAddedTask ->
      case string.trim(state.title) {
        "" -> #(state, effect.none())
        title -> {
          let #(tasks, _) = tasks.create(state.tasks, title)
          #(State(..state, tasks:, title: ""), effect.none())
        }
      }
    UserToggledTask(id, completed) -> {
      let tasks = case tasks.set_completed(state.tasks, id, completed) {
        Ok(tasks) -> tasks
        Error(Nil) -> state.tasks
      }
      #(State(..state, tasks:), effect.none())
    }
    UserToggledAll(completed) -> {
      let tasks = tasks.complete_all(state.tasks, completed)
      #(State(..state, tasks:), effect.none())
    }
    UserDeletedTask(id) -> {
      #(State(..state, tasks: tasks.delete(state.tasks, id)), effect.none())
    }
    UserClearedCompleted -> {
      #(
        State(..state, tasks: tasks.clear_completed(state.tasks)),
        effect.none(),
      )
    }
    UserChoseFilter(filter) -> #(State(..state, filter:), effect.none())
    UserStartedEditing(task) -> {
      #(State(..state, editing: Some(#(task.id, task.title))), effect.none())
    }
    UserEditedTask(title) ->
      case state.editing {
        Some(#(id, _)) -> #(
          State(..state, editing: Some(#(id, title))),
          effect.none(),
        )
        None -> #(state, effect.none())
      }
    UserFinishedEditing ->
      case state.editing {
        Some(#(id, title)) -> {
          let tasks = case string.trim(title) {
            "" -> tasks.delete(state.tasks, id)
            title ->
              case tasks.rename(state.tasks, id, title) {
                Ok(tasks) -> tasks
                Error(Nil) -> state.tasks
              }
          }
          #(State(..state, tasks:, editing: None), effect.none())
        }
        None -> #(state, effect.none())
      }
    UserCancelledEditing -> #(State(..state, editing: None), effect.none())
  }
}

const purpose =
  "You manage the user's todo list by writing EYG programs and running them with the run tool."

fn system(shell, guide) {
  agent.system_prompt(purpose, shell.text(shell, "todos", "readme"), guide)
}

fn responded(state: State, shell, body) {
  let workspace = #(shell, state.tasks, state.transcript)
  case agent.respond(state.agent, workspace, body, run_for_agent) {
    agent.Continue(agent:, state: #(shell, tasks, transcript), request:, ..) -> {
      let state = State(..state, agent:, shell: Ok(shell), tasks:, transcript:)
      #(state, send(request))
    }
    agent.Answered(agent:, state: #(shell, tasks, transcript), text:) -> {
      let transcript = [Said(Model, text), ..transcript]
      let state =
        State(
          ..state,
          agent:,
          shell: Ok(shell),
          tasks:,
          transcript:,
          thinking: False,
        )
      #(state, effect.none())
    }
    agent.Failed(agent:, reason:, ..) -> {
      let transcript = [Problem(reason), ..state.transcript]
      #(State(..state, agent:, thinking: False, transcript:), effect.none())
    }
  }
}

// The agent's runs go to the same shell and list, and into the transcript.
fn run_for_agent(workspace, code) {
  let #(shell, tasks, transcript) = workspace
  let result = run.run(shell, tasks, code)
  let transcript = [ran(Model, code, result), ..transcript]
  #(#(result.shell, result.tasks, transcript), run.report(result))
}

fn ran(by, code, result: run.Run) {
  let ok = case result.outcome {
    shell.Returned(_) -> True
    _ -> False
  }
  Ran(by:, code:, output: run.report(result), ok:)
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

// VIEW ------------------------------------------------------------------------

pub fn view(state: State) -> Element(Message) {
  h.div([a.class("page")], [console(state), todoapp(state)])
}

fn todoapp(state: State) {
  let all = tasks.all(state.tasks)
  let left = list.count(all, fn(task) { !task.completed })
  let shown =
    list.filter(all, fn(task) {
      case state.filter {
        All -> True
        Active -> !task.completed
        Completed -> task.completed
      }
    })
  h.div([a.class("app")], [
    h.section([a.class("todoapp")], [
      h.header([a.class("header")], [
        h.h1([], [h.text("todos")]),
        h.form([event.on_submit(fn(_) { UserAddedTask })], [
          h.input([
            a.class("new-todo"),
            a.placeholder("What needs to be done?"),
            a.value(state.title),
            event.on_input(UserEditedTitle),
          ]),
        ]),
      ]),
      case all {
        [] -> element.none()
        _ ->
          h.main([a.class("main")], [
            h.div([a.class("toggle-all-container")], [
              h.input([
                a.class("toggle-all"),
                a.id("toggle-all"),
                a.type_("checkbox"),
                a.checked(left == 0),
                event.on_check(UserToggledAll),
              ]),
              h.label([a.class("toggle-all-label"), a.for("toggle-all")], [
                h.text("Mark all as complete"),
              ]),
            ]),
            h.ul([a.class("todo-list")], list.map(shown, item(state, _))),
          ])
      },
      case all {
        [] -> element.none()
        _ -> footer(state, left, list.length(all) - left)
      },
    ]),
    h.p([a.class("info")], [
      h.text("Double-click to edit a todo. The console can do the rest."),
    ]),
  ])
}

fn item(state: State, task: Task) {
  let editing = case state.editing {
    Some(#(id, title)) if id == task.id -> Some(title)
    _ -> None
  }
  h.li(
    [
      a.classes([
        #("completed", task.completed),
        #("editing", option.is_some(editing)),
      ]),
    ],
    [
      h.div([a.class("view")], [
        h.input([
          a.class("toggle"),
          a.type_("checkbox"),
          a.checked(task.completed),
          event.on_check(UserToggledTask(task.id, _)),
        ]),
        h.label(
          [event.on("dblclick", decode.success(UserStartedEditing(task)))],
          [
            h.text(task.title),
          ],
        ),
        h.button(
          [
            a.class("destroy"),
            a.attribute("aria-label", "Delete " <> task.title),
            event.on_click(UserDeletedTask(task.id)),
          ],
          [],
        ),
      ]),
      case editing {
        Some(title) ->
          h.input([
            a.class("edit"),
            a.value(title),
            a.autofocus(True),
            event.on_input(UserEditedTask),
            event.on_blur(UserFinishedEditing),
            event.on_keydown(fn(key) {
              case key {
                "Escape" -> UserCancelledEditing
                "Enter" -> UserFinishedEditing
                _ -> UserEditedTask(title)
              }
            }),
          ])
        None -> element.none()
      },
    ],
  )
}

fn footer(state: State, left, completed) {
  let filter = fn(filter, href, label) {
    h.li([], [
      h.a(
        [
          a.href(href),
          a.classes([#("selected", state.filter == filter)]),
          event.on_click(UserChoseFilter(filter)) |> event.prevent_default,
        ],
        [h.text(label)],
      ),
    ])
  }
  h.footer([a.class("footer")], [
    h.span([a.class("todo-count")], [
      h.strong([], [h.text(int.to_string(left))]),
      h.text(case left {
        1 -> " item left"
        _ -> " items left"
      }),
    ]),
    h.ul([a.class("filters")], [
      filter(All, "#/", "All"),
      filter(Active, "#/active", "Active"),
      filter(Completed, "#/completed", "Completed"),
    ]),
    case completed {
      0 -> element.none()
      _ ->
        h.button(
          [a.class("clear-completed"), event.on_click(UserClearedCompleted)],
          [h.text("Clear completed")],
        )
    },
  ])
}

fn console(state: State) {
  h.section([a.class("console")], [
    h.header([a.class("tabs")], [
      tab(state, Console, "Shell"),
      tab(state, Chat, "Agent"),
    ]),
    h.ol([a.class("transcript")], case state.shell {
      Ok(_) -> list.map(state.transcript, entry)
      Error(reason) if reason == loading -> [
        h.li([a.class("loading")], [h.text(reason)]),
      ]
      Error(reason) -> [h.li([a.class("problem")], [h.text(reason)])]
    }),
    case state.mode {
      Console -> shell_input(state)
      Chat -> chat_input(state)
    },
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
    h.button([a.type_("submit"), a.disabled(result_is_error(state.shell))], [
      h.text("Run"),
    ]),
  ])
}

fn result_is_error(result) {
  case result {
    Ok(_) -> False
    Error(_) -> True
  }
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
          a.placeholder("Ask the agent to organise your tasks"),
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
