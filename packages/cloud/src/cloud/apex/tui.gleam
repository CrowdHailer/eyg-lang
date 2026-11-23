//// A terminal interface to boxes, and the shells and chats in them.
////
//// The named boxes are listed, one is opened by starting a shell or a chat in it, or in a transient copy of it.
//// A shell runs code, a chat is with one of the configured llms, whose tool calls run in shells of their own.
//// Work that waits for the database, a box or an llm runs in another process and reports back with a message.

import cloud/apex/context.{type Context}
import cloud/apex/terminal
import cloud/box
import cloud/chats/chat as chatting
import cloud/data/boxes.{type Box}
import cloud/data/chats.{type Chat}
import cloud/data/shells.{type Shell}
import cloud/shells/turn
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
  /// Choosing how to start a shell or chat from a named box.
  Open(box: Box, choices: List(Choice), selected: Int)
  Running(
    // Where the shell or chat is, for the title.
    place: String,
    thread: Thread,
    log: List(Entry),
    input: String,
    waiting: Bool,
  )
}

/// What a shell's log shows, each is coloured differently.
pub type Entry {
  Sent(String)
  Printed(String)
  Returned(String)
  Failed(String)
}

/// What is open, a shell or a chat.
pub type Thread {
  InShell(id: String, shell: Shell)
  InChat(id: String, chat: Chat)
}

/// A shell, or a chat with an llm, in the box or in a transient copy of it.
pub type Choice {
  Start(transient: Bool, llm: Option(String))
}

pub type Message {
  Key(String)
  Listed(Result(List(Box), box.Reason))
  Created(Result(Box, box.Reason))
  Started(Result(#(String, Thread), box.Reason))
  /// The outcome of a turn in the shell, or the reply of the chat, with this id.
  Replied(String, Result(turn.Outcome, box.Reason))
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

// Run work away from the interface's process, a failure leaves the interface waiting.
fn background(work: fn() -> Message) -> Effect(Message) {
  use dispatch <- effect.from
  process.spawn_unlinked(fn() { dispatch(work()) })
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
        "n" -> {
          let submit = fn(name) { Created(box.create(context, Some(name))) }
          let prompt = Prompt("Name of the new box", "", False, submit)
          #(Model(..model, prompt: Some(prompt)), effect.none())
        }
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
              background(fn() { Started(start(context, box, transient, llm)) }),
            )
            [] -> #(model, effect.none())
          }
        "esc" -> back(model)
        _ -> #(model, effect.none())
      }
    _, Started(Ok(#(place, thread))) -> #(
      Model(context, Running(place, thread, [], "", False), None, Quiet),
      effect.none(),
    )
    _, Started(Error(reason)) -> #(
      Model(..model, status: Problem(describe(reason))),
      effect.none(),
    )

    Running(waiting: True, ..), Key("esc") -> back(model)
    Running(waiting: True, ..), Key(_) -> #(model, effect.none())
    Running(thread:, log:, input:, ..) as running, Key(key) ->
      case key {
        "esc" -> back(model)
        "backspace" -> #(
          Model(
            ..model,
            screen: Running(..running, input: string.drop_end(input, 1)),
          ),
          effect.none(),
        )
        "enter" if input != "" -> {
          let log = list.append(log, [Sent(input)])
          #(
            Model(
              ..model,
              screen: Running(..running, log:, input: "", waiting: True),
            ),
            background(fn() { Replied(thread.id, send(context, thread, input)) }),
          )
        }
        _ ->
          case string.length(key) {
            1 -> #(
              Model(..model, screen: Running(..running, input: input <> key)),
              effect.none(),
            )
            _ -> #(model, effect.none())
          }
      }
    // A reply for a shell or chat that is no longer shown is dropped, it is in its journal.
    Running(thread:, log:, ..) as running, Replied(id, replied)
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
      let log = list.append(log, lines)
      #(
        Model(..model, screen: Running(..running, log:, waiting: False)),
        effect.none(),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

fn is_chat(thread: Thread) -> Bool {
  case thread {
    InChat(..) -> True
    InShell(..) -> False
  }
}

// Code runs as a turn of the shell, a message is sent to the chat and its reply is the outcome.
fn send(context, thread: Thread, input) -> Result(turn.Outcome, box.Reason) {
  case thread {
    InShell(shell:, ..) -> turn.send(context, shell, turn.Code(input))
    InChat(chat:, ..) -> {
      use replied <- result.map(chatting.send(context, chat, input))
      #(replied, [])
    }
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

/// Every way to start from a box, a shell or a chat with each of the configured llms.
pub fn choices(context: Context) -> List(Choice) {
  let llms = dict.keys(context.llms) |> list.sort(string.compare)
  list.flat_map([None, ..list.map(llms, Some)], fn(llm) {
    [Start(False, llm), Start(True, llm)]
  })
}

/// Start a shell in the box or a transient copy of it, or a chat if there is an llm.
/// Returns where it is.
/// A transient copy starts from the latest files of the box.
pub fn start(
  context: Context,
  named: Box,
  transient: Bool,
  llm: Option(String),
) -> Result(#(String, Thread), box.Reason) {
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
      #(place, InShell(shell.id, shell))
    }
    Some(llm) -> {
      use chat <- result.map(chatting.start(context, id, llm))
      #(place, InChat(chat.id, chat))
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

/// The screen as it is drawn.
pub fn render(model: Model) -> buffer.Buffer {
  let screen = buffer.buffer_new(geometry.rect_new(0, 0, width, height))
  let area = geometry.rect_new(0, 1, width, height - 3)
  let #(title, help) = case model.screen {
    Boxes(..) -> #("Boxes", [
      #("↑↓", "choose"),
      #("enter", "open"),
      #("n", "new box"),
      #("r", "refresh"),
    ])
    Open(box, ..) -> #(option.unwrap(box.name, box.id), [
      #("↑↓", "choose"),
      #("enter", "start"),
      #("esc", "back"),
    ])
    Running(place:, thread:, ..) -> #(
      case thread {
        InChat(..) -> "Chat in " <> place
        InShell(..) -> "Shell in " <> place
      },
      [#("enter", "send"), #("esc", "boxes")],
    )
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
        }
      })
      |> menu(screen, area, chosen)
    }
    Running(thread:, log:, input:, waiting:, ..) -> {
      let chat = is_chat(thread)
      let columns = area.size.width
      let rows = area.size.height - 1
      let lines =
        list.flat_map(log, fn(entry) {
          let #(prefix, content, style) = case entry, chat {
            Sent(text), True -> #(
              "you ",
              text,
              fg(accent) |> style.add_modifier(style.bold()),
            )
            Sent(text), False -> #("> ", text, fg(accent))
            Printed(text), _ -> #("", text, fg(muted))
            Returned(text), True -> #("llm ", text, fg(purple))
            Returned(text), False -> #("= ", text, fg(green))
            Failed(text), _ -> #("! ", text, fg(red))
          }
          string.split(prefix <> content, "\n")
          |> list.flat_map(text.wrap(_, columns))
          |> list.map(fn(line) { #(line, style) })
        })
      let shown = list.drop(lines, int.max(list.length(lines) - rows, 0))
      let screen =
        list.index_fold(shown, screen, fn(screen, line, i) {
          buffer.set_string(
            screen,
            Position(area.position.x, area.position.y + i),
            line.0,
            line.1,
          )
        })
      let prompt = case waiting {
        True -> [span.span_styled("waiting…", fg(muted))]
        False -> [
          span.span_styled("> ", fg(accent)),
          span.span_plain(text.truncate(input, columns - 3, "…")),
          span.span_styled("▏", fg(accent)),
        ]
      }
      span.render_line(
        screen,
        Position(area.position.x, area.position.y + rows),
        span.line_new(prompt),
        columns,
      )
    }
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
