//// A terminal interface to boxes, and the shells and chats in them.
////
//// The named boxes are listed, one is opened by starting a shell or a chat in it, or in a transient copy of it.
//// A shell runs code, a chat is with one of the configured llms, whose tool calls run in shells of their own.
//// Shells are durable, a recent shell or one with a known id is opened again from its history,
//// and a turn that did not finish is finished when it is opened.
//// Work that waits for the database, a box or an llm runs in another process and reports back with a message,
//// that process is watched so the interface is told if it stops.

import cloud/apex/context.{type Context, Context}
import cloud/apex/draft
import cloud/apex/editor
import cloud/apex/terminal
import cloud/artifacts
import cloud/beam/execute
import cloud/box
import cloud/chats/chat as chatting
import cloud/chats/event as chat_event
import cloud/data/boxes.{type Box}
import cloud/data/chats.{type Chat}
import cloud/data/shells.{type Shell}
import cloud/live
import cloud/shells/event
import cloud/shells/turn
import etui/buffer
import etui/geometry.{Position}
import etui/span
import etui/style
import etui/text
import etui/widgets/block
import etui/widgets/input
import etui/widgets/list as list_widget
import eyg/ir/dag_json
import gleam/dict
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import lustre
import lustre/effect.{type Effect}
import morph/terminal as code
import morph/terminal/field
import morph/terminal/textarea
import multiformats/cid/v1
import overlay/agent
import unixfs/mfs

/// The size of the screen before the page says how much fits.
pub const size = #(100, 30)

pub type Model {
  Model(
    context: Context,
    screen: Screen,
    // A line of text asked for over the screen.
    prompt: Option(Prompt),
    status: Status,
    // The columns and rows that fit on the page.
    size: #(Int, Int),
  )
}

/// A line of text asked for, it is submitted in another process and `masked` hides what is typed.
pub type Prompt {
  Prompt(
    label: String,
    input: input.InputState,
    masked: Bool,
    submit: fn(String) -> Message,
  )
}

pub type Status {
  Quiet
  Working(String)
  Problem(String)
}

pub type Screen {
  Boxes(boxes: List(Box), selected: Int)
  /// The most recent shells, in any box.
  /// Shells in transient boxes are only listed if `transient` is true.
  Recent(threads: List(#(Thread, String)), selected: Int, transient: Bool)
  /// Choosing how to start a shell or chat from a named box.
  Open(box: Box, choices: List(Choice), selected: Int)
  /// The names of a box's secrets, values are never shown.
  Secrets(box: Box, names: List(String), selected: Int)
  Running(
    // Where the shell or chat is, for the title.
    place: String,
    thread: Thread,
    log: List(Entry),
    draft: draft.Draft,
    waiting: Bool,
    // What the running turn has done so far.
    progress: List(String),
    // A completion as it arrives, it is replaced by the reply when the turn finishes.
    arriving: live.Arriving,
    // How many lines of the log are scrolled back.
    scroll: Int,
    // The files of the shell's box.
    files: Files,
    // A file shown beside the terminal.
    artifact: Option(Artifact),
  )
}

/// The files of a box and those a shell changed, the most recently changed last.
/// `latest` are the files the shell's last turn changed.
pub type Files {
  Files(
    root: v1.Cid,
    paths: List(String),
    changed: List(String),
    latest: List(String),
  )
}

/// A file as it was in the box at `root`.
pub type Artifact {
  Artifact(path: String, root: v1.Cid)
}

/// Where a file is read from by the page, see `cloud/apex/web`.
pub fn artifact_url(artifact: Artifact) -> String {
  "/artifacts/" <> v1.to_string(artifact.root) <> artifact.path
}

/// What a shell's log shows, each is coloured differently.
pub type Entry {
  Sent(String)
  /// A program as it was shown in the editor.
  Ran(List(span.Line))
  Printed(String)
  Returned(String)
  Failed(String)
  /// What an llm thought before a completion, only the latest thinking is shown in full.
  Thought(String)
}

/// What is open, a shell or a chat.
pub type Thread {
  InShell(id: String, shell: Shell)
  InChat(id: String, chat: Chat)
}

/// A shell, or a chat with an llm, in the box or in a transient copy of it.
pub type Choice {
  Start(transient: Bool, llm: Option(String))
  ManageSecrets
}

pub type Message {
  Key(String)
  Listed(Result(List(Box), box.Reason))
  Created(Result(Box, box.Reason))
  SecretsListed(Box, Result(List(String), box.Reason))
  /// The name of a secret to set, its value is asked for next.
  SecretNamed(String)
  RecentListed(Bool, Result(List(#(Thread, String)), box.Reason))
  Opened(Result(Opening, box.Reason))
  /// The outcome of a turn in the shell with this id.
  Replied(String, Result(turn.Outcome, box.Reason))
  /// A message was added to a chat that is replying.
  Added(Result(Nil, box.Reason))
  /// Work in another process stopped without a reply.
  Stopped(String)
  Pasted(String)
  /// Scroll the log back by lines, forward if negative.
  Scrolled(Int)
  Resized(columns: Int, rows: Int)
  /// What the running turn in the shell with this id has done so far.
  /// And the text of a completion it is receiving, empty if it is not.
  Progressed(String, List(String), live.Arriving)
  /// The files of the box of the shell with this id, a page the last turn changed is shown if `show` is true.
  FilesListed(String, Result(Files, box.Reason), show: Bool)
  /// The shell or chat with this id, read again from its journal once a turn finishes.
  Logged(String, Result(Opening, box.Reason))
  /// The column and row of the cell clicked.
  Clicked(Int, Int)
}

/// A shell or chat as it is shown when it is opened.
pub type Opening {
  Opening(
    place: String,
    thread: Thread,
    log: List(Entry),
    // The last turn is still running, or it stopped and will be finished.
    unfinished: Bool,
  )
}

pub fn app() -> lustre.App(Context, Model, Message) {
  lustre.application(init, update, view)
}

pub fn init(context: Context) -> #(Model, Effect(Message)) {
  #(
    Model(context, Boxes([], 0), None, Working("Loading boxes"), size),
    list_boxes(context),
  )
}

fn list_boxes(context) {
  background(fn() { Listed(box.named(context)) })
}

// Run work away from the interface's process. The work is watched and the interface is told if it stops.
fn background(work: fn() -> Message) -> Effect(Message) {
  use dispatch <- effect.from
  process.spawn_unlinked(fn() {
    let reply = process.new_subject()
    let worker = process.spawn_unlinked(fn() { process.send(reply, work()) })
    let monitor = process.monitor(worker)
    process.new_selector()
    |> process.select(reply)
    |> process.select_specific_monitor(monitor, fn(down) {
      Stopped(string.inspect(down.reason))
    })
    |> process.selector_receive_forever
    |> dispatch
  })
  Nil
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  let Model(screen:, prompt:, ..) = model
  case prompt, screen, message {
    Some(prompt), _, Key(key) -> #(ask(model, prompt, key), case key {
      "enter" -> background(fn() { prompt.submit(prompt.input.value) })
      _ -> effect.none()
    })
    _, _, Listed(Ok(boxes)) -> #(
      Model(..model, screen: Boxes(boxes, 0), prompt: None, status: case boxes {
        [] -> Working("There are no named boxes, press n to create one")
        _ -> Quiet
      }),
      effect.none(),
    )
    _, _, Listed(Error(reason)) | _, _, Created(Error(reason)) -> #(
      Model(..model, status: Problem(describe(reason))),
      effect.none(),
    )
    _, _, Created(Ok(_)) -> back(model)
    _, _, Resized(columns, rows) -> #(
      Model(..model, size: #(int.max(32, columns), int.max(10, rows))),
      effect.none(),
    )
    // A turn that stopped is in the shell's history, it is finished when the shell is opened again.
    _, Running(waiting: True, log:, ..) as running, Stopped(reason) -> #(
      Model(
        ..model,
        screen: Running(
          ..running,
          log: list.append(log, [Failed("The turn stopped: " <> reason)]),
          waiting: False,
        ),
        status: Quiet,
      ),
      effect.none(),
    )
    _, _, Stopped(reason) -> #(
      Model(..model, status: Problem("The work stopped: " <> reason)),
      effect.none(),
    )
    _, _, RecentListed(transient, Ok(threads)) -> #(
      Model(
        ..model,
        screen: Recent(threads, 0, transient),
        status: case threads {
          [] -> Working("There are no shells or chats yet")
          _ -> Quiet
        },
      ),
      effect.none(),
    )
    _, _, RecentListed(_, Error(reason)) | _, _, Opened(Error(reason)) -> #(
      Model(..model, status: Problem(describe(reason))),
      effect.none(),
    )
    _, _, Opened(Ok(opening)) -> opened(model, opening)
    _, _, Added(Ok(Nil)) -> #(model, effect.none())
    _, _, Added(Error(reason)) -> #(
      Model(..model, status: Problem(describe(reason))),
      effect.none(),
    )
    _, screen, message -> on_screen(model, screen, message)
  }
}

// Typing into the prompt, it is closed when it is submitted or cancelled.
fn ask(model, prompt: Prompt, key) {
  case key {
    "esc" -> Model(..model, prompt: None)
    "enter" -> Model(..model, prompt: None, status: Working("Working"))
    _ -> {
      let edited = field.edit(prompt_widget(prompt), prompt.input, key)
      Model(..model, prompt: Some(Prompt(..prompt, input: edited)))
    }
  }
}

fn prompt_widget(prompt: Prompt) {
  input.input_new("") |> input.with_password(prompt.masked)
}

fn on_screen(model: Model, screen, message) {
  let context = model.context
  case screen, message {
    Boxes(boxes, selected), Key(key) ->
      case key {
        "up" | "down" -> #(
          Model(..model, screen: Boxes(boxes, move(key, selected, boxes))),
          effect.none(),
        )
        "enter" ->
          case list.drop(boxes, selected) {
            [box, ..] -> #(
              Model(..model, screen: Open(box, choices(context), 0)),
              effect.none(),
            )
            [] -> #(model, effect.none())
          }
        "r" -> back(model)
        "s" -> #(
          Model(..model, status: Working("Loading shells")),
          background(fn() { RecentListed(False, recent(context, False)) }),
        )
        "o" -> {
          let submit = fn(id) { Opened(open(context, id)) }
          let prompt =
            Prompt("Id of the shell or chat", input.state_new(), False, submit)
          #(Model(..model, prompt: Some(prompt)), effect.none())
        }
        "n" -> {
          let submit = fn(name) { Created(box.create(context, Some(name))) }
          let prompt =
            Prompt("Name of the new box", input.state_new(), False, submit)
          #(Model(..model, prompt: Some(prompt)), effect.none())
        }
        _ -> #(model, effect.none())
      }

    Recent(threads, selected, transient), Key(key) ->
      case key {
        "up" | "down" -> #(
          Model(
            ..model,
            screen: Recent(threads, move(key, selected, threads), transient),
          ),
          effect.none(),
        )
        "t" -> #(
          Model(..model, status: Working("Loading shells")),
          background(fn() {
            RecentListed(!transient, recent(context, !transient))
          }),
        )
        "enter" ->
          case list.drop(threads, selected) {
            [#(thread, _), ..] -> #(
              Model(..model, status: Working("Opening")),
              background(fn() { Opened(open(context, thread.id)) }),
            )
            [] -> #(model, effect.none())
          }
        "esc" -> back(model)
        _ -> #(model, effect.none())
      }

    Open(box, choices, selected), Key(key) ->
      case key {
        "up" | "down" -> #(
          Model(
            ..model,
            screen: Open(box, choices, move(key, selected, choices)),
          ),
          effect.none(),
        )
        "enter" ->
          case list.drop(choices, selected) {
            [Start(transient, llm), ..] -> #(
              Model(..model, status: Working("Starting a shell")),
              background(fn() { Opened(start(context, box, transient, llm)) }),
            )
            [ManageSecrets, ..] -> #(
              Model(..model, status: Working("Loading secrets")),
              background(fn() { SecretsListed(box, secret_names(context, box)) }),
            )
            [] -> #(model, effect.none())
          }
        "esc" -> back(model)
        _ -> #(model, effect.none())
      }
    _, SecretsListed(box, Ok(names)) -> #(
      Model(..model, screen: Secrets(box, names, 0), status: Quiet),
      effect.none(),
    )
    _, SecretsListed(_, Error(reason)) -> #(
      Model(..model, status: Problem(describe(reason))),
      effect.none(),
    )
    Secrets(box, names, selected), Key(key) ->
      case key {
        "up" | "down" -> #(
          Model(
            ..model,
            screen: Secrets(box, names, move(key, selected, names)),
          ),
          effect.none(),
        )
        "a" -> {
          let prompt =
            Prompt("Name of the secret", input.state_new(), False, SecretNamed)
          #(Model(..model, prompt: Some(prompt)), effect.none())
        }
        "d" ->
          case list.drop(names, selected) {
            [name, ..] -> #(
              Model(..model, status: Working("Removing " <> name)),
              background(fn() {
                SecretsListed(box, {
                  use Nil <- result.try(box.delete_secret(context, box.id, name))
                  secret_names(context, box)
                })
              }),
            )
            [] -> #(model, effect.none())
          }
        "esc" -> #(
          Model(..model, screen: Open(box, choices(context), 0)),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    Secrets(box:, ..), SecretNamed(name) -> {
      let submit = fn(value) {
        SecretsListed(box, {
          use Nil <- result.try(box.set_secret(context, box.id, name, value))
          secret_names(context, box)
        })
      }
      let prompt = Prompt("Value of " <> name, input.state_new(), True, submit)
      #(Model(..model, prompt: Some(prompt), status: Quiet), effect.none())
    }
    Running(..) as running, Key("pageup") -> scroll(model, running, page(model))
    Running(..) as running, Key("pagedown") ->
      scroll(model, running, 0 - page(model))
    Running(..) as running, Scrolled(lines) -> scroll(model, running, lines)
    Running(thread:, waiting: True, ..), Key("ctrl+x") -> #(
      Model(..model, status: Working("Cancelling the turn")),
      background(fn() {
        Opened({
          use Nil <- result.try(case thread {
            InShell(shell:, ..) -> turn.cancel(context, shell)
            InChat(chat:, ..) -> chatting.cancel(context, chat)
          })
          open(context, thread.id)
        })
      }),
    )
    // A message can be written while a chat runs, code is written once a turn finishes.
    Running(waiting: True, draft: draft.Program(..), ..), Key("esc") ->
      back(model)
    Running(waiting: True, draft: draft.Program(..), ..), Key(_)
    | Running(waiting: True, draft: draft.Program(..), ..), Pasted(_)
    -> #(model, effect.none())
    Running(artifact: Some(_), ..) as running, Key("esc") -> #(
      Model(..model, screen: Running(..running, artifact: None)),
      effect.none(),
    )
    // The top line says the artifact closes when it is clicked.
    Running(artifact: Some(_), ..) as running, Clicked(_, 0) -> #(
      Model(..model, screen: Running(..running, artifact: None)),
      effect.none(),
    )
    Running(files:, ..) as running, Clicked(column, row) ->
      case pane_file(model.size, files.paths, column, row) {
        Ok(path) -> #(
          Model(
            ..model,
            screen: Running(
              ..running,
              artifact: Some(Artifact(path, files.root)),
            ),
          ),
          effect.none(),
        )
        Error(Nil) -> #(model, effect.none())
      }
    Running(draft: current, files:, ..) as running, Key(key) -> {
      let #(outcome, state) =
        draft.key(current, key, context.state, files.paths)
      drafted(
        Model(..model, context: Context(..context, state:)),
        running,
        key,
        outcome,
      )
    }
    Running(draft: current, ..) as running, Pasted(text) -> {
      let #(outcome, state) = draft.paste(current, text, context.state)
      drafted(
        Model(..model, context: Context(..context, state:)),
        running,
        "",
        outcome,
      )
    }
    Running(thread:, waiting: True, ..) as running,
      Progressed(id, progress, arriving)
      if id == thread.id
    -> #(
      Model(..model, screen: Running(..running, progress:, arriving:)),
      poll(context, thread),
    )
    // The page a turn changed last is shown, the files of a page are read from the root they were listed at.
    Running(thread:, artifact:, ..) as running, FilesListed(id, Ok(files), show)
      if id == thread.id
    -> {
      let shown = case show, list.filter(files.latest, artifacts.viewable) {
        True, [_, ..] as pages -> {
          let assert Ok(path) = list.last(pages)
          Some(Artifact(path, files.root))
        }
        _, _ ->
          option.map(artifact, fn(shown) { Artifact(..shown, root: files.root) })
      }
      #(
        Model(..model, screen: Running(..running, files:, artifact: shown)),
        effect.none(),
      )
    }
    // A turn that started since the log was read adds to the log, the next one read has it all.    // A message sent to a chat after its last reply is replied to next.
    Running(thread:, waiting: False, ..) as running, Logged(id, Ok(opening))
      if id == thread.id
    -> {
      let running = Running(..running, log: opening.log)
      case opening.unfinished, thread {
        True, InChat(chat:, ..) -> reply(model, running, chat)
        _, _ -> #(Model(..model, screen: running), effect.none())
      }
    }
    // A reply for a thread that is no longer shown is dropped, it is in the thread's history.
    // A message sent to a chat after its last reply is replied to next.
    Running(thread:, log:, waiting: True, ..) as running, Replied(id, replied)
      if id == thread.id
    -> {
      let lines = case replied {
        Ok(#(outcome, output)) ->
          list.map(output, Printed)
          |> list.append([
            case outcome {
              Ok(value) -> Returned(value)
              Error(reason) -> Failed(reason)
            },
          ])
        Error(reason) -> [Failed(describe(reason))]
      }
      // A reply too long for the screen is shown from its start,
      // two more lines are scrolled back as the lines above and below say there is more.
      let #(columns, rows) = log_size(model.size)
      let chat = draft.mode(running.draft) == "message"
      let reply = list.flat_map(lines, entry_lines(_, chat, columns))
      let log = list.append(log, lines)
      let running = Running(..running, log:)
      let scroll = case list.length(reply) > rows {
        True ->
          int.min(list.length(reply) - rows + 2, last_scroll(model, running))
        False -> 0
      }
      let running =
        Running(
          ..running,
          log:,
          waiting: False,
          progress: [],
          arriving: live.nothing,
          scroll:,
        )
      let model = Model(..model, screen: running)
      // The log is read again from the journal, which has the thinking of each completion.
      #(
        model,
        effect.batch([
          list_files(context, thread, True),
          background(fn() { Logged(thread.id, open(context, thread.id)) }),
        ]),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

// What a key or paste did to the draft. Escape leaves the shell if the draft does not use it.
fn drafted(model: Model, running, key, outcome) {
  let assert Running(..) = running
  case outcome {
    draft.Edited(edited) -> #(
      Model(..model, screen: Running(..running, draft: edited), status: Quiet),
      effect.none(),
    )
    draft.Send(input, next) -> send(model, running, input, next)
    draft.Problem(reason) -> #(
      Model(..model, status: Problem(reason)),
      effect.none(),
    )
    draft.Unhandled ->
      case key {
        "esc" -> back(model)
        _ -> #(model, effect.none())
      }
  }
}

// The lines a page up or down scrolls.
fn page(model: Model) {
  int.max(1, log_size(model.size).1 - 2)
}

// Scroll the log back by `lines`, forward if it is negative, from its end to its first line.
fn scroll(model: Model, running, lines) {
  let assert Running(scroll:, ..) = running
  let scroll = int.clamp(scroll + lines, 0, last_scroll(model, running))
  #(Model(..model, screen: Running(..running, scroll:)), effect.none())
}

// How far the log scrolls back before its first line is at the top.
fn last_scroll(model: Model, running) {
  let assert Running(log:, draft: current, ..) = running
  let #(columns, rows) = log_size(model.size)
  let chat = draft.mode(current) == "message"
  let lines = log_lines(log, chat, columns, False) |> list.length
  int.max(0, lines - rows)
}

// A wide screen shows the files of the box beside the shell.
const pane = 26

// Before the files are listed.
const no_files = Files(dag_json.vacant_cid, [], [], [])

// The file on the row clicked in the files beside the shell, there are none on a narrow screen.
// The files start below the frame's top and the title of the files.
fn pane_file(size: #(Int, Int), paths, column, row) {
  let #(width, _) = size
  case width - 2 >= 90 && column >= width - 1 - pane {
    True -> list.drop(paths, row - 3) |> list.first
    False -> Error(Nil)
  }
}

// The columns and rows of a shell's log, inside the frame, beside the files and above a one line draft.
fn log_size(size: #(Int, Int)) {
  let #(width, height) = size
  let inner = width - 2
  let columns = case inner >= 90 {
    True -> inner - pane - 1
    False -> inner
  }
  #(columns, height - 6)
}

// Check what a running turn has done, again and again while it runs.
fn poll(context: Context, thread: Thread) {
  background(fn() {
    process.sleep(700)
    let id = thread.id
    case thread {
      InShell(shell:, ..) ->
        case turn.history(context, shell.id) {
          Ok(history) ->
            Progressed(
              id,
              progress(list.map(history, fn(entry) { entry.1 })),
              live.nothing,
            )
          Error(_) -> Progressed(id, [], live.nothing)
        }
      InChat(chat:, ..) ->
        case chatting.entries(context, chat.id) {
          Ok(entries) ->
            Progressed(
              id,
              chat_progress(entries),
              live.arriving(context.live, chat.id),
            )
          Error(_) -> Progressed(id, [], live.nothing)
        }
    }
  })
}

/// What a chat is doing, asking the llm or running its tool calls.
pub fn chat_progress(entries: List(chat_event.Entry)) -> List(String) {
  case chat_event.next(entries) {
    chat_event.Idle(_) -> []
    chat_event.Ask(_) -> ["asking the llm"]
    chat_event.Call(calls) ->
      list.map(calls, fn(call) {
        case agent.cast_tool_call(call.function.name, call.function.arguments) {
          Ok(agent.Run(code)) -> "running " <> first_line(code)
          Error(_) -> "calling " <> call.function.name
        }
      })
  }
}

/// What the last turn in a shell's entries has done, such as making requests.
pub fn progress(entries: List(event.Entry)) -> List(String) {
  last_turn(entries)
  |> list.flat_map(fn(entry) {
    case entry {
      event.Output(stop: event.Requested(request), ..) -> [
        http.method_to_string(request.method)
        |> string.uppercase
        <> " "
        <> uri.to_string(request.to_uri(request)),
      ]
      event.Output(stop: event.Slept(milliseconds), ..) -> [
        "sleeping " <> int.to_string(milliseconds) <> "ms",
      ]
      event.Output(change: event.Rejected(reason), ..) -> [
        "changes rejected, " <> first_line(string.replace(reason, "\n", " ")),
      ]
      _ -> []
    }
  })
}

// The entries of the last turn, from the input that started it.
fn last_turn(entries) {
  let #(turn, start) =
    list.reverse(entries)
    |> list.split_while(fn(entry) {
      case entry {
        event.Input(trigger, ..) -> !event.starts(trigger)
        _ -> True
      }
    })
  list.reverse(list.append(turn, list.take(start, 1)))
}

fn first_line(text) {
  case string.split(string.trim(text), "\n") {
    [line] -> line
    [line, ..] -> line <> " …"
    [] -> ""
  }
}

fn list_files(context: Context, thread: Thread, show) {
  background(fn() { FilesListed(thread.id, files(context, thread), show) })
}

/// The path of every file in the box, and the files the shell, or the shells of the chat, changed.
pub fn files(context: Context, thread: Thread) -> Result(Files, box.Reason) {
  let failed = fn(reason) { box.Failed(string.inspect(reason)) }
  let box = case thread {
    InShell(shell:, ..) -> shell.box
    InChat(chat:, ..) -> chat.box
  }
  use box <- result.try(box.latest(context, box))
  use paths <- result.try(
    execute.files(mfs.files(box.root), context.state)
    |> result.map(list.map(_, fn(path) { "/" <> string.join(path, "/") }))
    |> result.map_error(failed),
  )
  use #(entries, latest) <- result.try(case thread {
    InShell(shell:, ..) -> {
      use history <- result.map(turn.history(context, shell.id))
      let entries = list.map(history, fn(entry) { entry.1 })
      #(entries, last_turn(entries))
    }
    InChat(chat:, ..) -> {
      use shells <- result.try(chatting.shells(context, chat.id))
      use chatted <- result.try(chatting.entries(context, chat.id))
      let calls = last_calls(chatted)
      use ran <- result.map(
        list.try_map(shells, fn(ran) {
          let #(shell, call) = ran
          use history <- result.map(turn.history(context, shell.id))
          #(list.map(history, fn(entry) { entry.1 }), call)
        }),
      )
      #(
        list.flat_map(ran, fn(ran) { ran.0 }),
        list.flat_map(ran, fn(ran) {
          case ran.1 {
            Some(call) ->
              case list.contains(calls, call) {
                True -> ran.0
                False -> []
              }
            None -> []
          }
        }),
      )
    }
  })
  use changed <- result.try(
    artifacts.changed(entries, context.state) |> result.map_error(box.Failed),
  )
  use latest <- result.map(
    artifacts.changed(latest, context.state) |> result.map_error(box.Failed),
  )
  Files(box.root, paths, changed, latest)
}

// The tool calls of the chat's last turn, from the message that started it.
fn last_calls(entries) {
  list.fold(entries, #([], False), fn(acc, entry) {
    let #(calls, ended) = acc
    case entry, ended {
      chat_event.Sent(_), True -> #([], False)
      chat_event.Replied(completion), _ -> #(
        list.append(
          calls,
          list.map(completion.tool_calls, fn(call) { call.id }),
        ),
        completion.tool_calls == [],
      )
      chat_event.Failed(_), _ | chat_event.Cancelled, _ -> #(calls, True)
      _, _ -> acc
    }
  }).0
}

// Send code to the shell or a message to the chat, its outcome is added to the log when it is replied to.
// A message sent while a chat is replying is added to the chat after the tool calls that are running.
fn send(model: Model, running, input, draft) {
  let assert Running(thread:, log:, waiting:, ..) = running
  let running = Running(..running, log: list.append(log, [sent(input)]), draft:)
  case waiting, thread, input {
    True, InChat(chat:, ..), draft.Said(message) -> #(
      Model(..model, screen: Running(..running, scroll: 0), status: Quiet),
      background(fn() { Added(chatting.add(model.context, chat, message)) }),
    )
    _, _, _ -> run_turn(model, running, input)
  }
}

// Reply to messages sent to the chat that have no reply.
fn reply(model: Model, running, chat: Chat) {
  let assert Running(..) = running
  let context = model.context
  let screen =
    Running(
      ..running,
      waiting: True,
      progress: [],
      arriving: live.nothing,
      scroll: 0,
    )
  #(
    Model(..model, screen:, status: Quiet),
    effect.batch([
      background(fn() {
        Replied(chat.id, {
          use replied <- result.map(chatting.reply(context, chat))
          #(replied, [])
        })
      }),
      poll(context, InChat(chat.id, chat)),
    ]),
  )
}

// Start a turn that is already in the log.
fn run_turn(model: Model, running, input) {
  let assert Running(thread:, ..) = running
  let screen =
    Running(
      ..running,
      waiting: True,
      progress: [],
      arriving: live.nothing,
      scroll: 0,
    )
  #(
    Model(..model, screen:, status: Quiet),
    effect.batch([
      background(fn() {
        Replied(thread.id, turn_or_reply(model.context, thread, input))
      }),
      poll(model.context, thread),
    ]),
  )
}

// How code or a message is shown in the log.
fn sent(input: draft.Sent) {
  case input {
    draft.Said(text) -> Sent(text)
    draft.Ran(turn.Code(source)) ->
      Ran(code.highlight(source) |> list.map(span.line_new))
    draft.Ran(turn.Program(program)) -> Ran(editor.program_lines(program))
  }
}

// Show a shell or chat, a turn that has not finished is finished first.
fn opened(model: Model, opening: Opening) {
  let Opening(place:, thread:, log:, unfinished:) = opening
  // The draft, files and artifact are kept when it is opened again after its turn finishes.
  let #(draft, files, artifact) = case model.screen, thread {
    Running(thread: shown, draft:, files:, artifact:, ..), _
      if shown.id == thread.id
    -> #(draft, files, artifact)
    _, InChat(..) -> #(draft.message(), no_files, None)
    _, InShell(..) -> #(draft.program(), no_files, None)
  }
  let screen =
    Running(
      place,
      thread,
      log,
      draft,
      unfinished,
      [],
      live.nothing,
      0,
      files,
      artifact,
    )
  let model = Model(..model, screen:, status: Quiet)
  let files = list_files(model.context, thread, False)
  case unfinished {
    False -> #(model, files)
    True -> #(
      model,
      effect.batch([
        files,
        poll(model.context, thread),
        background(fn() { resume(model.context, thread) }),
      ]),
    )
  }
}

// Finish the last turn of a shell, or reply to the messages a chat has not replied to.
fn resume(context: Context, thread: Thread) -> Message {
  case thread {
    InShell(shell:, ..) ->
      Opened({
        use Nil <- result.try(turn.resume(context, shell))
        open(context, shell.id)
      })
    InChat(chat:, ..) ->
      Replied(chat.id, {
        use replied <- result.map(chatting.reply(context, chat))
        #(replied, [])
      })
  }
}

fn recent(context, transient) {
  use shells <- result.try(turn.recent(context, 20, transient))
  use chats <- result.map(chatting.recent(context, 20, transient))
  list.append(
    list.map(shells, fn(entry) {
      let #(shell, name, at) = entry
      #(at, #(InShell(shell.id, shell), option.unwrap(name, "a transient box")))
    }),
    list.map(chats, fn(entry) {
      let #(chat, name, at) = entry
      #(at, #(InChat(chat.id, chat), option.unwrap(name, "a transient box")))
    }),
  )
  |> list.sort(fn(a, b) { int.compare(b.0, a.0) })
  |> list.take(20)
  |> list.map(fn(entry) { entry.1 })
}

/// A shell or chat as it is shown, with everything that has happened in it.
pub fn open(context: Context, id: String) -> Result(Opening, box.Reason) {
  case turn.find(context, id) {
    Ok(shell) -> {
      use box <- result.try(box.latest(context, shell.box))
      use history <- result.map(turn.history(context, id))
      let entries = list.map(history, fn(entry) { entry.1 })
      let place = option.unwrap(box.name, "a transient box")
      Opening(
        place,
        InShell(shell.id, shell),
        log(entries),
        turn.unfinished_turn(entries),
      )
    }
    Error(box.Missing) -> {
      use chat <- result.try(chatting.find(context, id))
      use box <- result.try(box.latest(context, chat.box))
      use entries <- result.map(chatting.entries(context, id))
      let place = option.unwrap(box.name, "a transient box")
      let unfinished = case chat_event.next(entries) {
        chat_event.Idle(_) -> False
        _ -> True
      }
      Opening(place, InChat(chat.id, chat), chat_log(entries), unfinished)
    }
    Error(reason) -> Error(reason)
  }
}

// What the entries of a chat show, the messages, the llm's thinking and its replies.
fn chat_log(entries) {
  list.flat_map(entries, fn(entry) {
    case entry {
      chat_event.Sent(message) -> [Sent(message)]
      chat_event.Replied(completion) ->
        case completion.thinking {
          "" -> []
          thinking -> [Thought(thinking)]
        }
        |> list.append(case completion.tool_calls {
          [] -> [Returned(completion.content)]
          _ -> []
        })
      chat_event.Failed(reason) -> [Failed(reason)]
      chat_event.Cancelled -> [Failed("cancelled")]
      chat_event.Returned(..) -> []
    }
  })
}

// What the entries of a shell show.
fn log(entries) {
  list.flat_map(entries, fn(entry) {
    case entry {
      event.Input(event.Started(code, _), ..) -> [
        sent(draft.Ran(turn.Code(code))),
      ]
      event.Input(event.Submitted(program, _), ..) -> [
        sent(draft.Ran(turn.Program(program))),
      ]
      event.Input(event.Cancelled, ..) -> [Failed("cancelled")]
      event.Output(stop: event.Finished(_, output) as stop, change:, ..) ->
        list.map(output, Printed)
        |> list.append([
          case turn.outcome(stop, change) {
            Ok(value) -> Returned(value)
            Error(reason) -> Failed(reason)
          },
        ])
      _ -> []
    }
  })
}

// Code runs as a turn of the shell, a message is sent to the chat and its reply is the outcome.
fn turn_or_reply(
  context,
  thread: Thread,
  sent: draft.Sent,
) -> Result(turn.Outcome, box.Reason) {
  case thread, sent {
    InShell(shell:, ..), draft.Ran(input) -> turn.send(context, shell, input)
    InChat(chat:, ..), draft.Said(message) -> {
      use replied <- result.map(chatting.send(context, chat, message))
      #(replied, [])
    }
    _, _ ->
      Error(box.Failed("a shell runs code and a chat replies to messages"))
  }
}

// Back to the list of boxes, which may have changed.
fn back(model: Model) {
  #(Model(..model, status: Working("Loading boxes")), list_boxes(model.context))
}

fn move(key, selected, items) {
  case key {
    "up" -> int.max(selected - 1, 0)
    _ -> int.min(selected + 1, list.length(items) - 1)
  }
}

/// Every way to start a shell from a box, with each of the configured llms, then its secrets.
pub fn choices(context: Context) -> List(Choice) {
  let llms = dict.keys(context.llms) |> list.sort(string.compare)
  list.flat_map([None, ..list.map(llms, Some)], fn(llm) {
    [Start(False, llm), Start(True, llm)]
  })
  |> list.append([ManageSecrets])
}

fn secret_names(context, box: Box) {
  use secrets <- result.map(box.secrets(context, box.id))
  dict.keys(secrets) |> list.sort(string.compare)
}

/// Start a shell in the box or a transient copy of it, or a chat if there is an llm.
/// A transient copy starts from the latest files of the box.
pub fn start(
  context: Context,
  named: Box,
  transient: Bool,
  llm: Option(String),
) -> Result(Opening, box.Reason) {
  let name = option.unwrap(named.name, named.id)
  use #(id, place) <- result.try(case transient {
    False -> Ok(#(named.id, name))
    True -> {
      use latest <- result.try(box.latest(context, named.id))
      use copy <- result.map(box.clone(context, latest, None))
      #(copy.id, "a transient copy of " <> name)
    }
  })
  case llm {
    None -> {
      use shell <- result.map(turn.start(context, id))
      Opening(place, InShell(shell.id, shell), [], False)
    }
    Some(llm) -> {
      use chat <- result.map(chatting.start(context, id, llm))
      Opening(place, InChat(chat.id, chat), [], False)
    }
  }
}

fn describe(reason) {
  case reason {
    box.Missing -> "The box is gone"
    box.Taken -> "The name is taken"
    box.Conflict(paths) ->
      "Files changed elsewhere: " <> string.join(paths, ", ")
    box.Invalid(errors) -> string.join(errors, ", ")
    box.Failed(reason) -> reason
  }
}

pub fn view(model: Model) {
  let artifact = case model.screen {
    Running(artifact: Some(artifact), ..) -> Some(artifact_url(artifact))
    _ -> None
  }
  terminal.view(
    render(model),
    artifact,
    Key,
    Pasted,
    Resized,
    Scrolled,
    Clicked,
  )
}

// The colours of the interface, the code uses the editor's own.
const accent = style.Rgb(97, 175, 239)

const muted = style.Rgb(110, 118, 134)

const green = style.Rgb(152, 195, 121)

const red = style.Rgb(224, 108, 117)

const purple = style.Rgb(198, 120, 221)

const selected = style.Rgb(38, 56, 84)

fn fg(color) {
  style.default_style() |> style.with_fg(color)
}

fn title(running) {
  let assert Running(place:, draft: current, ..) = running
  case current {
    draft.Message(..) -> "Chat in " <> place
    draft.Program(..) -> "Shell in " <> place
  }
}

/// The screen as it is drawn.
pub fn render(model: Model) -> buffer.Buffer {
  let #(width, height) = model.size
  let screen = buffer.buffer_new(geometry.rect_new(0, 0, width, height))
  let area = geometry.rect_new(0, 1, width, height - 3)
  let #(title, help) = case model.screen {
    Boxes(..) -> #("Boxes", [
      #("↑↓", "choose"),
      #("enter", "open"),
      #("n", "new box"),
      #("s", "shells"),
      #("o", "open by id"),
      #("r", "refresh"),
    ])
    Recent(transient:, ..) -> #(
      case transient {
        True -> "Recent shells, with transient boxes"
        False -> "Recent shells"
      },
      [
        #("↑↓", "choose"),
        #("enter", "open"),
        #("t", case transient {
          True -> "hide transient"
          False -> "show transient"
        }),
        #("esc", "back"),
      ],
    )
    Running(waiting: True, draft: draft.Message(..), ..) as running -> #(
      title(running),
      [
        #("enter", "add to chat"),
        #("shift+enter", "new line"),
        #("ctrl+x", "cancel"),
        #("esc", "boxes"),
      ],
    )
    Running(waiting: True, ..) as running -> #(title(running), [
      #("ctrl+x", "cancel"),
      #("esc", "boxes"),
    ])
    Secrets(box, ..) -> #("Secrets of " <> option.unwrap(box.name, box.id), [
      #("↑↓", "choose"),
      #("a", "add"),
      #("d", "delete"),
      #("esc", "back"),
    ])
    Open(box, ..) -> #(option.unwrap(box.name, box.id), [
      #("↑↓", "choose"),
      #("enter", "start"),
      #("esc", "back"),
    ])
    Running(draft: draft.Message(..), ..) as running -> #(title(running), [
      #("enter", "send"),
      #("shift+enter", "new line"),
      #("ctrl+←→", "word"),
      #("pgup/pgdn", "scroll"),
      #("esc", "boxes"),
    ])
    Running(draft: draft.Program(structured: False, ..), ..) as running -> #(
      title(running),
      [
        #("enter", "run"),
        #("shift+enter", "new line"),
        #("ctrl+←→", "word"),
        #("tab", "structured"),
        #("pgup/pgdn", "scroll"),
        #("esc", "boxes"),
      ],
    )
    Running(
      draft: draft.Program(
        structured: True,
        editor: editor.Editor(input: Some(editor.Picking(..)), ..),
        ..,
      ),
      ..,
    ) as running -> #(title(running), [
      #("↑↓", "choose"),
      #("tab", "complete"),
      #("enter", "pick"),
      #("esc", "cancel"),
    ])
    Running(
      draft: draft.Program(
        structured: True,
        editor: editor.Editor(input: Some(editor.Typed(..)), ..),
        ..,
      ),
      ..,
    ) as running -> #(title(running), [
      #("←→", "move"),
      #("enter", "apply"),
      #("esc", "cancel"),
    ])
    Running(draft: draft.Program(..), ..) as running -> #(title(running), [
      #("enter", "run"),
      #("tab", "text"),
      #("n", "number"),
      #("s", "string"),
      #("v", "variable"),
      #("j", "builtin"),
      #("c", "call"),
      #("e", "let"),
      #("p", "perform"),
      #("q", "import"),
      #("z", "undo"),
    ])
  }
  let frame =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_style(muted, style.Default)
    |> block.with_title_styled(
      [
        span.span_styled(
          " " <> title <> " ",
          fg(accent) |> style.add_modifier(style.bold()),
        ),
      ],
      block.Top,
    )
  let inner = block.inner(area, frame)
  let help =
    list.flat_map(help, fn(entry) {
      [
        span.span_styled(" " <> entry.0, fg(accent)),
        span.span_styled(" " <> entry.1 <> " ", fg(muted)),
      ]
    })
  screen
  |> spans(0, width, [
    span.span_styled(" EYG", fg(accent) |> style.add_modifier(style.bold())),
    span.span_styled(" cloud", fg(muted)),
    ..case model.screen {
      Running(artifact: Some(artifact), ..) -> [
        span.span_styled("  ✕ close", fg(accent)),
        span.span_styled(" " <> artifact.path, fg(green)),
        span.span_styled("  esc or click this line", fg(muted)),
      ]
      _ -> []
    }
  ])
  |> block.render(area, frame)
  |> body(inner, model)
  |> spans(height - 2, width, help)
  |> spans(height - 1, width, case model.status {
    Quiet -> []
    Working(text) -> [span.span_styled(" " <> text, fg(muted))]
    Problem(text) -> [span.span_styled(" " <> text, fg(red))]
  })
  |> dialog(model.prompt, model.size)
  // A variable, builtin, package or file being chosen is in a box over the middle of the screen.
  |> fn(screen) {
    case model.screen {
      Running(draft: draft.Program(structured: True, editor: edited, ..), ..) ->
        editor.render_input(edited, screen, area)
      _ -> screen
    }
  }
}

// The prompt in a box over the middle of the screen.
fn dialog(screen, prompt, size: #(Int, Int)) {
  let #(width, height) = size
  case prompt {
    None -> screen
    Some(Prompt(label:, input: editing, ..) as prompt) ->
      field.dialog(
        screen,
        geometry.rect_new(0, 0, width, height),
        label,
        prompt_widget(prompt),
        editing,
      )
  }
}

fn spans(screen, y, width, spans) {
  span.render_line(screen, Position(0, y), span.line_new(spans), width)
}

fn body(screen, area: geometry.Rect, model: Model) {
  case model.screen {
    Boxes(boxes, chosen) ->
      list.map(boxes, fn(box) { option.unwrap(box.name, box.id) })
      |> menu(screen, area, chosen)
    Recent(threads, chosen, _) ->
      list.map(threads, fn(entry) {
        let #(thread, place) = entry
        thread.id <> "  in " <> place
      })
      |> menu(screen, area, chosen)
    Open(box, choices, chosen) -> {
      let name = option.unwrap(box.name, box.id)
      list.map(choices, fn(choice) {
        case choice {
          Start(transient, llm) -> {
            let kind = case llm {
              Some(llm) -> "Chat with " <> llm
              None -> "Shell"
            }
            case transient {
              True -> kind <> " in a transient copy of " <> name
              False -> kind <> " in " <> name
            }
          }
          ManageSecrets -> "Secrets of " <> name
        }
      })
      |> menu(screen, area, chosen)
    }
    Secrets(names: [], ..) ->
      buffer.set_string(
        screen,
        area.position,
        "No secrets, press a to add one",
        fg(muted),
      )
    Secrets(names:, selected: chosen, ..) ->
      list.map(names, fn(name) { name <> "  ••••••" })
      |> menu(screen, area, chosen)
    Running(
      log:,
      draft: current,
      waiting:,
      progress:,
      arriving:,
      scroll:,
      files:,
      artifact:,
      ..,
    ) -> {
      let #(area, screen) = case area.size.width >= 90 {
        True -> #(
          geometry.rect_new(
            area.position.x,
            area.position.y,
            area.size.width - pane - 1,
            area.size.height,
          ),
          file_pane(
            screen,
            geometry.rect_new(
              area.position.x + area.size.width - pane,
              area.position.y,
              pane,
              area.size.height,
            ),
            files,
            artifact,
          ),
        )
        False -> #(area, screen)
      }
      let columns = area.size.width
      let chat = draft.mode(current) == "message"
      let lines =
        log_lines(log, chat, columns, waiting && arriving.thinking != "")
      // A draft taller than half the area shows the part around its cursor.
      let drafted = fn(most) {
        let #(lines, cursor) = draft.lines(current, True, columns - 2)
        let most = int.max(3, most)
        let start =
          int.clamp(cursor - most + 1, 0, int.max(0, list.length(lines) - most))
        prompted(list.drop(lines, start) |> list.take(most))
      }
      let below = case waiting {
        True ->
          list.map(progress, fn(step) {
            span.line_new([span.span_styled("· " <> step, fg(muted))])
          })
          // The thinking and text of a completion as they arrive, the end of them if they are long.
          |> list.append({
            let lines =
              list.flat_map(
                [Thought(arriving.thinking), Returned(arriving.text)],
                fn(entry) {
                  case entry {
                    Thought("") | Returned("") -> []
                    _ -> entry_lines(entry, True, columns)
                  }
                },
              )
            list.drop(lines, list.length(lines) - area.size.height / 2)
          })
          |> list.append([
            span.line_new([span.span_styled("waiting…", fg(muted))]),
          ])
          // A message can be written for the chat while it runs.
          |> list.append(case chat {
            True -> drafted(area.size.height / 4)
            False -> []
          })
        False -> drafted(area.size.height / 2)
      }
      let rows = int.max(0, area.size.height - list.length(below))
      // Scrolling back shows earlier lines, it stops at the first.
      let total = list.length(lines)
      let scroll = int.min(scroll, int.max(0, total - rows))
      let start = int.max(0, total - rows - scroll)
      let shown = list.drop(lines, start) |> list.take(rows)
      let shown = case start > 0, shown {
        True, [_, ..rest] -> [
          span.line_new([
            span.span_styled(
              "↑ " <> int.to_string(start + 1) <> " earlier lines, page up",
              fg(muted),
            ),
          ]),
          ..rest
        ]
        _, _ -> shown
      }
      let shown = case scroll > 0 {
        True ->
          list.take(shown, list.length(shown) - 1)
          |> list.append([
            span.line_new([
              span.span_styled("↓ newer lines, page down", fg(muted)),
            ]),
          ])
        False -> shown
      }
      // The shell fills the screen from the bottom, as a terminal does, the log grows up from the draft.
      let lines = list.append(shown, below)
      let top =
        area.position.y + int.max(0, area.size.height - list.length(lines))
      list.index_fold(lines, screen, fn(screen, line, i) {
        span.render_line(
          screen,
          Position(area.position.x, top + i),
          line,
          columns,
        )
      })
    }
  }
}

// The files the shell changed are coloured, the one shown is reversed.
fn file_pane(screen, area: geometry.Rect, files: Files, artifact) {
  let screen =
    list.index_fold(
      list.repeat(Nil, area.size.height),
      screen,
      fn(screen, _, i) {
        buffer.set_string(
          screen,
          Position(area.position.x - 1, area.position.y + i),
          "│",
          fg(muted),
        )
      },
    )
  [
    span.line_new([span.span_styled(" files", fg(accent))]),
    ..case files.paths {
      [] -> [span.line_new([span.span_styled(" none yet", fg(muted))])]
      paths ->
        list.map(paths, fn(path) {
          let style = case list.contains(files.changed, path) {
            True -> fg(green)
            False -> style.default_style()
          }
          let style = case artifact {
            Some(Artifact(path: shown, ..)) if shown == path ->
              style.add_modifier(style, style.reverse())
            _ -> style
          }
          span.line_new([
            span.span_plain(" "),
            span.span_styled(
              text.truncate(path, area.size.width - 1, "…"),
              style,
            ),
          ])
        })
    }
  ]
  |> list.take(area.size.height)
  |> list.index_fold(screen, fn(screen, line, i) {
    span.render_line(
      screen,
      Position(area.position.x, area.position.y + i),
      line,
      area.size.width,
    )
  })
}

// Code starts with a prompt and the lines after it are lined up with it.
fn prompted(lines) {
  list.index_map(lines, fn(line, i) {
    let prompt = case i {
      0 -> "> "
      _ -> "  "
    }
    span.Line(..line, spans: [
      span.span_styled(prompt, fg(accent)),
      ..line.spans
    ])
  })
}

fn entry_lines(entry, chat, columns) {
  let text = fn(prefix, content, style) {
    string.split(prefix <> content, "\n")
    |> list.flat_map(text.wrap(_, columns))
    |> list.map(fn(line) { span.line_new([span.span_styled(line, style)]) })
  }
  case entry, chat {
    // Code is wrapped beside its prompt.
    Ran(lines), _ ->
      list.flat_map(lines, fn(line) { textarea.wrap(line.spans, columns - 2) })
      |> prompted
    Sent(content), _ ->
      text("you ", content, fg(accent) |> style.add_modifier(style.bold()))
    Printed(content), _ -> text("", content, fg(muted))
    Returned(content), True -> text("llm ", content, fg(purple))
    Returned(content), False -> text("= ", content, fg(green))
    Failed(content), _ -> text("! ", content, fg(red))
    Thought(content), _ ->
      text("thinking ", content, fg(muted) |> style.add_modifier(style.dim()))
  }
}

// The lines of the log, only the latest thinking is shown in full, earlier thinking is a line saying how long it is.
// When an llm is thinking now that is the latest.
fn log_lines(log, chat, columns, thinking_now) {
  let latest = case thinking_now {
    True -> -1
    False ->
      list.index_fold(log, -1, fn(latest, entry, i) {
        case entry {
          Thought(_) -> i
          _ -> latest
        }
      })
  }
  list.index_map(log, fn(entry, i) {
    case entry {
      Thought(content) if i != latest -> {
        let lines = list.length(string.split(content, "\n"))
        let lines = case lines {
          1 -> "1 line"
          _ -> int.to_string(lines) <> " lines"
        }
        [
          span.line_new([span.span_styled("▸ thought for " <> lines, fg(muted))]),
        ]
      }
      _ -> entry_lines(entry, chat, columns)
    }
  })
  |> list.flatten
}

fn menu(items, screen, area, chosen) {
  list_widget.list_new(items)
  |> list_widget.with_highlight_style(
    fg(style.Rgb(255, 255, 255))
    |> style.with_bg(selected)
    |> style.add_modifier(style.bold()),
  )
  |> list_widget.render_stateful(
    screen,
    area,
    _,
    list_widget.ListState(chosen, 0),
  )
}
