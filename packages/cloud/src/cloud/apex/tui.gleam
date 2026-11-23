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
import etui/style
import etui/text
import etui/widgets/block
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
  Model(context: Context, screen: Screen, status: String)
}

pub type Screen {
  Boxes(boxes: List(Box), selected: Int)
  /// Choosing how to start a shell or chat from a named box.
  Open(box: Box, choices: List(Choice), selected: Int)
  Running(
    // Where the shell or chat is, for the title.
    place: String,
    thread: Thread,
    log: List(String),
    input: String,
    waiting: Bool,
  )
}

/// What is open, a shell or a chat.
pub type Thread {
  InShell(id: String, shell: Shell)
  InChat(id: String, chat: Chat)
}

/// A shell, or a chat with an llm, in the box or in a transient copy of it.
pub type Choice {
  Choice(transient: Bool, llm: Option(String))
}

pub type Message {
  Key(String)
  Listed(Result(List(Box), box.Reason))
  Started(Result(#(String, Thread), box.Reason))
  /// The outcome of a turn in the shell, or the reply of the chat, with this id.
  Replied(String, Result(turn.Outcome, box.Reason))
}

pub fn app() -> lustre.App(Context, Model, Message) {
  lustre.application(init, update, view)
}

pub fn init(context: Context) -> #(Model, Effect(Message)) {
  #(Model(context, Boxes([], 0), "Loading boxes"), list_boxes(context))
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
  let Model(context:, screen:, ..) = model
  case screen, message {
    _, Listed(Ok(boxes)) -> #(
      Model(context, Boxes(boxes, 0), case boxes {
        [] -> "There are no named boxes, create one with POST /boxes"
        _ -> ""
      }),
      effect.none(),
    )
    _, Listed(Error(reason)) -> #(
      Model(..model, status: describe(reason)),
      effect.none(),
    )

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
        "r" -> #(Model(..model, status: "Loading boxes"), list_boxes(context))
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
            [choice, ..] -> #(
              Model(..model, status: "Starting a shell"),
              background(fn() { Started(start(context, box, choice)) }),
            )
            [] -> #(model, effect.none())
          }
        "esc" -> back(model)
        _ -> #(model, effect.none())
      }
    _, Started(Ok(#(place, thread))) -> #(
      Model(context, Running(place, thread, [], "", False), ""),
      effect.none(),
    )
    _, Started(Error(reason)) -> #(
      Model(..model, status: describe(reason)),
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
          let sent = case thread {
            InChat(..) -> "you: " <> input
            InShell(..) -> "> " <> input
          }
          let log = list.append(log, [sent])
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
      let chat = case thread {
        InChat(..) -> True
        InShell(..) -> False
      }
      let lines = case replied {
        Ok(#(outcome, output)) ->
          list.append(output, [
            case outcome, chat {
              Ok(value), True -> "llm: " <> value
              Ok(value), False -> "= " <> value
              Error(reason), _ -> "! " <> reason
            },
          ])
        Error(reason) -> ["! " <> describe(reason)]
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

// Code runs as a turn of the shell, a message is sent to the chat and its reply is the outcome.
fn send(context, thread: Thread, input) -> Result(turn.Outcome, box.Reason) {
  case thread {
    InShell(shell:, ..) -> turn.send(context, shell, input)
    InChat(chat:, ..) -> {
      use replied <- result.map(chatting.send(context, chat, input))
      #(replied, [])
    }
  }
}

// Back to the list of boxes, which may have changed.
fn back(model: Model) {
  #(Model(..model, status: "Loading boxes"), list_boxes(model.context))
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
    [Choice(False, llm), Choice(True, llm)]
  })
}

/// Start a shell or a chat as chosen, and the place it is in.
/// A transient copy starts from the latest files of the box.
pub fn start(
  context: Context,
  named: Box,
  choice: Choice,
) -> Result(#(String, Thread), box.Reason) {
  let name = option.unwrap(named.name, named.id)
  use #(id, place) <- result.try(case choice.transient {
    False -> Ok(#(named.id, name))
    True -> {
      use latest <- result.try(box.latest(context, named.id))
      use copy <- result.map(box.clone(context, latest, None))
      #(copy.id, "a transient copy of " <> name)
    }
  })
  case choice.llm {
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

/// The screen as it is drawn.
pub fn render(model: Model) -> buffer.Buffer {
  let screen = buffer.buffer_new(geometry.rect_new(0, 0, width, height))
  let area = geometry.rect_new(0, 1, width, height - 3)
  let #(title, help) = case model.screen {
    Boxes(..) -> #("Boxes", "↑↓ choose  enter open  r refresh")
    Open(box, ..) -> #(
      option.unwrap(box.name, box.id),
      "↑↓ choose  enter start  esc back",
    )
    Running(place:, thread:, ..) -> #(
      case thread {
        InChat(..) -> "Chat in " <> place
        InShell(..) -> "Shell in " <> place
      },
      "enter send  esc boxes",
    )
  }
  let frame =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title(" " <> title <> " ", block.Top)
  let inner = block.inner(area, frame)
  screen
  |> line(0, " EYG cloud", style.bold_style())
  |> block.render(area, frame)
  |> body(inner, model)
  |> line(height - 2, " " <> help, style.dim_style())
  |> line(height - 1, " " <> model.status, style.default_style())
}

fn line(screen, y, content, style) {
  buffer.set_string(
    screen,
    Position(0, y),
    text.truncate(content, width, "…"),
    style,
  )
}

fn body(screen, area: geometry.Rect, model: Model) {
  case model.screen {
    Boxes(boxes, selected) ->
      list.map(boxes, fn(box) { option.unwrap(box.name, box.id) })
      |> menu(screen, area, selected)
    Open(box, choices, selected) -> {
      let name = option.unwrap(box.name, box.id)
      list.map(choices, fn(choice) {
        let kind = case choice.llm {
          Some(llm) -> "Chat with " <> llm
          None -> "Shell"
        }
        case choice.transient {
          True -> kind <> " in a transient copy of " <> name
          False -> kind <> " in " <> name
        }
      })
      |> menu(screen, area, selected)
    }
    Running(log:, input:, waiting:, ..) -> {
      let columns = area.size.width
      let rows = area.size.height - 1
      let lines =
        list.flat_map(log, fn(entry) {
          string.split(entry, "\n") |> list.flat_map(text.wrap(_, columns))
        })
      let shown = list.drop(lines, int.max(list.length(lines) - rows, 0))
      let screen =
        list.index_fold(shown, screen, fn(screen, content, i) {
          buffer.set_string(
            screen,
            Position(area.position.x, area.position.y + i),
            content,
            style.default_style(),
          )
        })
      let prompt = case waiting {
        True -> #("waiting…", style.dim_style())
        False -> #(
          text.truncate("> " <> input, columns - 1, "…") <> "▏",
          style.default_style(),
        )
      }
      buffer.set_string(
        screen,
        Position(area.position.x, area.position.y + rows),
        prompt.0,
        prompt.1,
      )
    }
  }
}

fn menu(items, screen, area, selected) {
  list_widget.list_new(items)
  |> list_widget.render_stateful(
    screen,
    area,
    _,
    list_widget.ListState(selected, 0),
  )
}
