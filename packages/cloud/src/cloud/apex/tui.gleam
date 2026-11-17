//// A terminal interface to boxes and their sessions.
////
//// The named boxes are listed, one is opened by starting a session in it, or in a transient copy of it.
//// A session runs code as a shell, or chats with one of the configured llms.
//// Sessions are durable, a recent session or one with a known id is opened again from its history,
//// and a turn that did not finish is finished when it is opened.
//// Work that waits for the database, a box or an llm runs in another process and reports back with a message,
//// that process is watched so the interface is told if it stops.

import cloud/apex/context.{type Context, Context}
import cloud/apex/editor
import cloud/apex/terminal
import cloud/box
import cloud/data/boxes.{type Box}
import cloud/data/sessions.{type Session}
import cloud/sessions/event
import cloud/sessions/turn
import etui/buffer
import etui/geometry.{Position}
import etui/span
import etui/style
import etui/text
import etui/widgets/block
import etui/widgets/clear
import etui/widgets/list as list_widget
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/effect.{type Effect}

pub const width = 100

pub const height = 30

pub type Model {
  Model(
    context: Context,
    screen: Screen,
    // A line of text asked for over the screen.
    prompt: Option(Prompt),
    status: Status,
  )
}

/// A line of text asked for, it is submitted in another process and `masked` hides what is typed.
pub type Prompt {
  Prompt(
    label: String,
    input: String,
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
    draft: Draft,
    waiting: Bool,
  )
}

/// What is being written in a session, a message in a chat and a program in a shell.
pub type Draft {
  Chatting(String)
  Coding(editor.Editor)
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
    Model(context, Boxes([], 0), None, Working("Loading boxes")),
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
  let Model(context:, screen:, prompt:, ..) = model
  case prompt, screen, message {
    Some(prompt), _, Key(key) -> #(ask(model, prompt, key), case key {
      "enter" -> background(fn() { prompt.submit(prompt.input) })
      _ -> effect.none()
    })
    _, _, Listed(Ok(boxes)) -> #(
      Model(context, Boxes(boxes, 0), None, case boxes {
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
    "backspace" ->
      Model(
        ..model,
        prompt: Some(Prompt(..prompt, input: string.drop_end(prompt.input, 1))),
      )
    _ ->
      case string.length(key) {
        1 ->
          Model(
            ..model,
            prompt: Some(Prompt(..prompt, input: prompt.input <> key)),
          )
        _ -> model
      }
  }
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
          let prompt = Prompt("Id of the session", "", False, submit)
          #(Model(..model, prompt: Some(prompt)), effect.none())
        }
        "n" -> {
          let submit = fn(name) { Created(box.create(context, Some(name))) }
          let prompt = Prompt("Name of the new box", "", False, submit)
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
          let prompt = Prompt("Name of the secret", "", False, SecretNamed)
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
      let prompt = Prompt("Value of " <> name, "", True, submit)
      #(Model(..model, prompt: Some(prompt), status: Quiet), effect.none())
    }
    Running(waiting: True, ..), Key("esc") -> back(model)
    Running(session:, waiting: True, ..), Key("x") -> #(
      Model(..model, status: Working("Cancelling the turn")),
      background(fn() {
        Opened({
          use Nil <- result.try(turn.cancel(context, session))
          open(context, session.id)
        })
      }),
    )
    Running(waiting: True, ..), Key(_) -> #(model, effect.none())
    Running(draft: Chatting(text), ..) as running, Key(key) ->
      case key {
        "esc" -> back(model)
        "enter" if text != "" ->
          send(model, running, Sent(text), turn.Message(text), Chatting(""))
        "backspace" -> #(
          Model(
            ..model,
            screen: Running(
              ..running,
              draft: Chatting(string.drop_end(text, 1)),
            ),
          ),
          effect.none(),
        )
        _ ->
          case string.length(key) {
            1 -> #(
              Model(
                ..model,
                screen: Running(..running, draft: Chatting(text <> key)),
              ),
              effect.none(),
            )
            _ -> #(model, effect.none())
          }
      }
    Running(draft: Coding(editor.Editor(input: None, ..)), ..), Key("esc") ->
      back(model)
    Running(draft: Coding(editor.Editor(input: None, ..) as edited), ..) as running,
      Key("enter")
    ->
      case editor.program(edited) {
        Ok(program) ->
          send(
            model,
            running,
            Ran(editor.sent(edited)),
            turn.Program(program),
            Coding(editor.new()),
          )
        Error(Nil) -> #(
          Model(..model, status: Problem("Write a program first")),
          effect.none(),
        )
      }
    Running(draft: Coding(edited), ..) as running, Key(key) -> {
      let #(edited, state) = editor.key(edited, key, context.state)
      let model = Model(..model, context: Context(..context, state:))
      case edited {
        Ok(edited) -> #(
          Model(
            ..model,
            screen: Running(..running, draft: Coding(edited)),
            status: Quiet,
          ),
          effect.none(),
        )
        Error(reason) -> #(
          Model(..model, status: Problem(reason)),
          effect.none(),
        )
      }
    }
    // A reply for a session that is no longer shown is dropped, it is in the session's history.
    Running(session:, log:, waiting: True, ..) as running, Replied(id, replied)
      if id == session.id
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
      let log = list.append(log, lines)
      #(
        Model(..model, screen: Running(..running, log:, waiting: False)),
        effect.none(),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

// Send a turn to the session, its outcome is added to the log when it is replied to.
fn send(model: Model, running, entry, input, draft) {
  let assert Running(session:, log:, ..) = running
  let screen =
    Running(..running, log: list.append(log, [entry]), draft:, waiting: True)
  #(
    Model(..model, screen:, status: Quiet),
    background(fn() {
      Replied(session.id, turn.send(model.context, session, input))
    }),
  )
}

// Show a session, a turn that has not finished is finished first.
fn opened(model: Model, opening: Opening) {
  let Opening(place:, session:, log:, chat:, unfinished:) = opening
  let draft = case chat {
    True -> Chatting("")
    False -> Coding(editor.new())
  }
  let screen = Running(place, session, log, draft, unfinished)
  let model = Model(..model, screen:, status: Quiet)
  case unfinished {
    False -> #(model, effect.none())
    True -> #(
      model,
      background(fn() {
        Opened({
          use Nil <- result.try(turn.resume(model.context, session))
          open(model.context, session.id)
        })
      }),
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
      event.Started(code, _) -> [
        Ran(string.split(code, "\n") |> list.map(span.line_plain)),
      ]
      event.Submitted(program, _) -> [Ran(editor.program_lines(program))]
      event.Sent(message, _) -> [Sent(message)]
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
  terminal.view(render(model), Key)
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
  let assert Running(place:, draft:, ..) = running
  case draft {
    Chatting(_) -> "Chat in " <> place
    Coding(_) -> "Shell in " <> place
  }
}

/// The screen as it is drawn.
pub fn render(model: Model) -> buffer.Buffer {
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
    Running(waiting: True, ..) as running -> #(title(running), [
      #("x", "cancel"),
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
    Running(draft: Chatting(_), ..) as running -> #(title(running), [
      #("enter", "send"),
      #("esc", "boxes"),
    ])
    Running(draft: Coding(_), ..) as running -> #(title(running), [
      #("enter", "run"),
      #("n", "number"),
      #("s", "string"),
      #("v", "variable"),
      #("j", "builtin"),
      #("c", "call"),
      #("e", "let"),
      #("p", "perform"),
      #("z", "undo"),
      #("esc", "boxes"),
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
  |> spans(0, [
    span.span_styled(" EYG", fg(accent) |> style.add_modifier(style.bold())),
    span.span_styled(" cloud", fg(muted)),
  ])
  |> block.render(area, frame)
  |> body(inner, model)
  |> spans(height - 2, help)
  |> spans(height - 1, case model.status {
    Quiet -> []
    Working(text) -> [span.span_styled(" " <> text, fg(muted))]
    Problem(text) -> [span.span_styled(" " <> text, fg(red))]
  })
  |> dialog(model.prompt)
}

// The prompt in a box over the middle of the screen.
fn dialog(screen, prompt) {
  case prompt {
    None -> screen
    Some(Prompt(label:, input:, masked:, ..)) -> {
      let area = geometry.rect_new(20, height / 2 - 2, width - 40, 3)
      let frame =
        block.block_new()
        |> block.with_border(block.Rounded)
        |> block.with_style(accent, style.Default)
        |> block.with_bg_fill
        |> block.with_title_styled(
          [span.span_styled(" " <> label <> " ", fg(accent))],
          block.Top,
        )
      let inner = block.inner(area, frame)
      let shown = case masked {
        True -> string.repeat("•", string.length(input))
        False -> input
      }
      screen
      |> clear.render(area)
      |> block.render(area, frame)
      |> span.render_line(
        inner.position,
        span.line_new([
          span.span_plain(text.truncate(shown, inner.size.width - 1, "…")),
          span.span_styled("▏", fg(accent)),
        ]),
        inner.size.width,
      )
    }
  }
}

fn spans(screen, y, spans) {
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
    Running(log:, draft:, waiting:, ..) -> {
      let columns = area.size.width
      let chat = case draft {
        Chatting(_) -> True
        Coding(_) -> False
      }
      let lines = list.flat_map(log, entry_lines(_, chat, columns))
      let draft = case waiting, draft {
        True, _ -> [span.line_new([span.span_styled("waiting…", fg(muted))])]
        False, Chatting(text) -> [
          span.line_new([
            span.span_styled("> ", fg(accent)),
            span.span_plain(text.truncate(text, columns - 3, "…")),
            span.span_styled("▏", fg(accent)),
          ]),
        ]
        False, Coding(edited) -> prompted(editor.lines(edited, True))
      }
      // The end of the log is shown above the draft.
      let rows = area.size.height - list.length(draft)
      let shown = list.drop(lines, int.max(list.length(lines) - rows, 0))
      list.append(shown, draft)
      |> list.index_fold(screen, fn(screen, line, i) {
        span.render_line(
          screen,
          Position(area.position.x, area.position.y + i),
          line,
          columns,
        )
      })
    }
  }
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
    Ran(lines), _ -> prompted(lines)
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
