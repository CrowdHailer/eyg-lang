//// A terminal interface to boxes and their sessions.
////
//// The named boxes are listed, one is opened by starting a session in it, or in a transient copy of it.
//// A session runs code as a shell, or chats with one of the configured llms.
//// Sessions are durable, a recent session or one with a known id is opened again from its history,
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
import cloud/data/boxes.{type Box}
import cloud/data/sessions.{type Session}
import cloud/live
import cloud/sessions/event
import cloud/sessions/turn
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
  /// The most recent sessions, in any box.
  /// Sessions in transient boxes are only listed if `transient` is true.
  Recent(sessions: List(#(Session, String)), selected: Int, transient: Bool)
  /// Choosing how to start a session from a named box.
  Open(box: Box, choices: List(Choice), selected: Int)
  /// The names of a box's secrets, values are never shown.
  Secrets(box: Box, names: List(String), selected: Int)
  Running(
    // Where the session is, for the title.
    place: String,
    session: Session,
    log: List(Entry),
    draft: draft.Draft,
    waiting: Bool,
    // What the running turn has done so far.
    progress: List(String),
    // The text of a completion as it arrives, it is replaced by the reply when the turn finishes.
    arriving: String,
    // How many lines of the log are scrolled back.
    scroll: Int,
    // The files of the session's box.
    files: Files,
    // A file shown beside the terminal.
    artifact: Option(Artifact),
  )
}

/// The files of a box and those a session changed, the most recently changed last.
/// `latest` are the files the session's last turn changed.
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

/// What a session's log shows, each is coloured differently.
pub type Entry {
  Sent(String)
  /// A program as it was shown in the editor.
  Ran(List(span.Line))
  Printed(String)
  Returned(String)
  Failed(String)
}

/// A session in the box or in a transient copy of it, that runs code or chats with an llm.
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
  RecentListed(Bool, Result(List(#(Session, String)), box.Reason))
  Opened(Result(Opening, box.Reason))
  /// The outcome of a turn in the session with this id.
  Replied(String, Result(turn.Outcome, box.Reason))
  /// Work in another process stopped without a reply.
  Stopped(String)
  Pasted(String)
  /// Scroll the log back by lines, forward if negative.
  Scrolled(Int)
  Resized(columns: Int, rows: Int)
  /// What the running turn in the session with this id has done so far.
  /// And the text of a completion it is receiving, empty if it is not.
  Progressed(String, List(String), String)
  /// The files of the box of the session with this id, a page the last turn changed is shown if `show` is true.
  FilesListed(String, Result(Files, box.Reason), show: Bool)
  /// The column and row of the cell clicked.
  Clicked(Int, Int)
}

/// A session as it is shown when it is opened.
pub type Opening {
  Opening(
    place: String,
    session: Session,
    log: List(Entry),
    chat: Bool,
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
    // A turn that stopped is in the session's history, it is finished when the session is opened again.
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
    _, _, RecentListed(transient, Ok(sessions)) -> #(
      Model(
        ..model,
        screen: Recent(sessions, 0, transient),
        status: case sessions {
          [] -> Working("There are no sessions yet")
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
          Model(..model, status: Working("Loading sessions")),
          background(fn() { RecentListed(False, recent(context, False)) }),
        )
        "o" -> {
          let submit = fn(id) { Opened(open(context, id)) }
          let prompt =
            Prompt("Id of the session", input.state_new(), False, submit)
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

    Recent(sessions, selected, transient), Key(key) ->
      case key {
        "up" | "down" -> #(
          Model(
            ..model,
            screen: Recent(sessions, move(key, selected, sessions), transient),
          ),
          effect.none(),
        )
        "t" -> #(
          Model(..model, status: Working("Loading sessions")),
          background(fn() {
            RecentListed(!transient, recent(context, !transient))
          }),
        )
        "enter" ->
          case list.drop(sessions, selected) {
            [#(session, _), ..] -> #(
              Model(..model, status: Working("Opening the session")),
              background(fn() { Opened(open(context, session.id)) }),
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
              Model(..model, status: Working("Starting a session")),
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
    Running(session:, waiting: True, ..), Key("ctrl+x") -> #(
      Model(..model, status: Working("Cancelling the turn")),
      background(fn() {
        Opened({
          use Nil <- result.try(turn.cancel(context, session))
          open(context, session.id)
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
    Running(session:, waiting: True, ..) as running,
      Progressed(id, progress, arriving)
      if id == session.id
    -> #(
      Model(..model, screen: Running(..running, progress:, arriving:)),
      poll(context, session),
    )
    // The page a turn changed last is shown, the files of a page are read from the root they were listed at.
    Running(session:, artifact:, ..) as running,
      FilesListed(id, Ok(files), show)
      if id == session.id
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
    // A reply for a session that is no longer shown is dropped, it is in the session's history.
    // Messages sent after the chat's last tool calls start the next turn.
    Running(session:, log:, waiting: True, ..) as running, Replied(id, replied)
      if id == session.id
    -> {
      let unsent = live.take(context.live, session.id)
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
          arriving: "",
          scroll:,
        )
      let model = Model(..model, screen: running)
      case unsent {
        [] -> #(model, list_files(context, session, True))
        _ -> {
          let #(model, effects) =
            run_turn(model, running, turn.Message(string.join(unsent, "\n\n")))
          #(model, effect.batch([effects, list_files(context, session, True)]))
        }
      }
    }
    _, _ -> #(model, effect.none())
  }
}

// What a key or paste did to the draft. Escape leaves the session if the draft does not use it.
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
  let lines = list.flat_map(log, entry_lines(_, chat, columns)) |> list.length
  int.max(0, lines - rows)
}

// A wide screen shows the files of the box beside the session.
const pane = 26

// Before the files are listed.
const no_files = Files(dag_json.vacant_cid, [], [], [])

// The file on the row clicked in the files beside the session, there are none on a narrow screen.
// The files start below the frame's top and the title of the files.
fn pane_file(size: #(Int, Int), paths, column, row) {
  let #(width, _) = size
  case width - 2 >= 90 && column >= width - 1 - pane {
    True -> list.drop(paths, row - 3) |> list.first
    False -> Error(Nil)
  }
}

// The columns and rows of a session's log, inside the frame, beside the files and above a one line draft.
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
fn poll(context, session: Session) {
  background(fn() {
    process.sleep(700)
    case turn.history(context, session.id) {
      Ok(history) ->
        Progressed(
          session.id,
          progress(list.map(history, fn(entry) { entry.2 })),
          live.text(context.live, session.id),
        )
      Error(_) -> Progressed(session.id, [], "")
    }
  })
}

/// What the last turn in the events has done, such as asking the llm and running its tool calls.
pub fn progress(events: List(event.Event)) -> List(String) {
  last_turn(events)
  |> list.flat_map(fn(event) {
    case event {
      event.Asked(..) -> ["asking the llm"]
      event.Answered(execute.Completed(Ok(completion))) ->
        list.filter_map(completion.tool_calls, fn(call) {
          case
            agent.cast_tool_call(call.function.name, call.function.arguments)
          {
            Ok(agent.Run(code)) -> Ok("running " <> first_line(code))
            Error(_) -> Error(Nil)
          }
        })
      event.Requested(request, _) -> [
        http.method_to_string(request.method)
        |> string.uppercase
        <> " "
        <> uri.to_string(request.to_uri(request)),
      ]
      event.Slept(milliseconds, _) -> [
        "sleeping " <> int.to_string(milliseconds) <> "ms",
      ]
      event.Answered(execute.Rejected(reason)) -> [
        "changes rejected, " <> first_line(string.replace(reason, "\n", " ")),
      ]
      _ -> []
    }
  })
}

// The events after the last turn started.
fn last_turn(events) {
  list.reverse(events)
  |> list.take_while(fn(event) {
    case event {
      event.Started(..) | event.Submitted(..) | event.Sent(..) -> False
      _ -> True
    }
  })
  |> list.reverse
}

fn first_line(text) {
  case string.split(string.trim(text), "\n") {
    [line] -> line
    [line, ..] -> line <> " …"
    [] -> ""
  }
}

fn list_files(context: Context, session: Session, show) {
  background(fn() { FilesListed(session.id, files(context, session), show) })
}

/// The path of every file in the session's box, and the files the session changed.
pub fn files(context: Context, session: Session) -> Result(Files, box.Reason) {
  let failed = fn(reason) { box.Failed(string.inspect(reason)) }
  use box <- result.try(box.latest(context, session.box))
  use paths <- result.try(
    execute.files(mfs.files(box.root), context.state)
    |> result.map(list.map(_, fn(path) { "/" <> string.join(path, "/") }))
    |> result.map_error(failed),
  )
  use history <- result.try(turn.history(context, session.id))
  let events = list.map(history, fn(entry) { entry.2 })
  use changed <- result.try(
    artifacts.changed(events, context.state) |> result.map_error(box.Failed),
  )
  use latest <- result.map(
    artifacts.changed(last_turn(events), context.state)
    |> result.map_error(box.Failed),
  )
  Files(box.root, paths, changed, latest)
}

// Send a turn to the session, its outcome is added to the log when it is replied to.
// A message sent while a chat runs is added to the chat when the llm's tool calls finish,
// or starts the next turn.
fn send(model: Model, running, input, draft) {
  let assert Running(session:, log:, waiting:, ..) = running
  let running = Running(..running, log: list.append(log, [sent(input)]), draft:)
  case waiting, input {
    True, turn.Message(message) -> {
      live.steer(model.context.live, session.id, message)
      #(
        Model(..model, screen: Running(..running, scroll: 0), status: Quiet),
        effect.none(),
      )
    }
    _, _ -> run_turn(model, running, input)
  }
}

// Start a turn that is already in the log.
fn run_turn(model: Model, running, input) {
  let assert Running(session:, ..) = running
  let screen =
    Running(..running, waiting: True, progress: [], arriving: "", scroll: 0)
  #(
    Model(..model, screen:, status: Quiet),
    effect.batch([
      background(fn() {
        Replied(session.id, turn.send(model.context, session, input))
      }),
      poll(model.context, session),
    ]),
  )
}

// How something sent to a session is shown in its log.
fn sent(input) {
  case input {
    turn.Message(text) -> Sent(text)
    turn.Code(source) -> Ran(code.highlight(source) |> list.map(span.line_new))
    turn.Program(program) -> Ran(editor.program_lines(program))
  }
}

// Show a session, a turn that has not finished is finished first.
fn opened(model: Model, opening: Opening) {
  let Opening(place:, session:, log:, chat:, unfinished:) = opening
  // The draft, files and artifact are kept when the session is opened again after its turn finishes.
  let #(draft, files, artifact) = case model.screen, chat {
    Running(session: shown, draft:, files:, artifact:, ..), _
      if shown.id == session.id
    -> #(draft, files, artifact)
    _, True -> #(draft.message(), no_files, None)
    _, False -> #(draft.program(), no_files, None)
  }
  let screen =
    Running(place, session, log, draft, unfinished, [], "", 0, files, artifact)
  let model = Model(..model, screen:, status: Quiet)
  let files = list_files(model.context, session, False)
  case unfinished {
    False -> #(model, files)
    True -> #(
      model,
      effect.batch([
        files,
        poll(model.context, session),
        background(fn() {
          Opened({
            use Nil <- result.try(turn.resume(model.context, session))
            open(model.context, session.id)
          })
        }),
      ]),
    )
  }
}

fn recent(context, transient) {
  use sessions <- result.map(turn.recent(context, 20, transient))
  list.map(sessions, fn(entry) {
    let #(session, name) = entry
    #(session, option.unwrap(name, "a transient box"))
  })
}

/// A session as it is shown, with everything that has happened in it.
pub fn open(context: Context, id: String) -> Result(Opening, box.Reason) {
  use session <- result.try(turn.find(context, id))
  use box <- result.try(box.latest(context, session.box))
  use history <- result.map(turn.history(context, id))
  let events = list.map(history, fn(entry) { entry.2 })
  let chat = case events {
    [event.Configured(_), ..] -> True
    _ -> False
  }
  let place = option.unwrap(box.name, "a transient box")
  Opening(place, session, log(events), chat, turn.unfinished_turn(events))
}

// What the events of a session show.
fn log(events) {
  list.flat_map(events, fn(event) {
    case event {
      event.Started(code, _) -> [sent(turn.Code(code))]
      event.Submitted(program, _) -> [sent(turn.Program(program))]
      event.Sent(message, _) -> [sent(turn.Message(message))]
      event.Answered(execute.Steered(messages)) ->
        list.map(messages, fn(message) { sent(turn.Message(message)) })
      event.Finished(outcome, output, _) ->
        list.map(output, Printed)
        |> list.append([
          case outcome {
            Ok(value) -> Returned(value)
            Error(reason) -> Failed(reason)
          },
        ])
      _ -> []
    }
  })
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

/// Every way to start a session from a box, with each of the configured llms, then its secrets.
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

/// Start a session in the box or a transient copy of it, it chats if there is an llm.
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
  use session <- result.map(turn.start(context, id, llm))
  Opening(place, session, [], option.is_some(llm), False)
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
      #("s", "sessions"),
      #("o", "open by id"),
      #("r", "refresh"),
    ])
    Recent(transient:, ..) -> #(
      case transient {
        True -> "Recent sessions, with transient boxes"
        False -> "Recent sessions"
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
    Recent(sessions, chosen, _) ->
      list.map(sessions, fn(entry) {
        let #(session, place) = entry
        session.id <> "  in " <> place
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
      let lines = list.flat_map(log, entry_lines(_, chat, columns))
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
          // The text of a completion as it arrives, the end of it if it is long.
          |> list.append(case arriving {
            "" -> []
            text -> {
              let lines = entry_lines(Returned(text), True, columns)
              list.drop(lines, list.length(lines) - area.size.height / 2)
            }
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
      // The session fills the screen from the bottom, as a terminal does, the log grows up from the draft.
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

// The files the session changed are coloured, the one shown is reversed.
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
  }
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
