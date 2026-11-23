import cloud/apex/context.{Context}
import cloud/apex/tui.{Key}
import cloud/box
import cloud/chats/chat
import cloud/helpers
import cloud/server
import cloud/shells/turn
import etui/buffer
import etui/geometry.{Position}
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string

// The text on the screen, one string for each row.
fn screen(model) {
  let screen = tui.render(model)
  list.repeat(Nil, buffer.height(screen))
  |> list.index_map(fn(_, y) {
    list.repeat(Nil, buffer.width(screen))
    |> list.index_map(fn(_, x) {
      buffer.get_cell(screen, Position(x, y)) |> buffer.cell_symbol
    })
    |> string.concat
  })
  |> string.join("\n")
}

fn press(model, keys) {
  list.fold(keys, model, fn(model, key) { tui.update(model, Key(key)).0 })
}

pub fn list_named_boxes_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Ok(_) = box.clone(context, home, None)
  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.Listed(box.named(context)))
  assert string.contains(screen(model), "home")
  let assert tui.Boxes(boxes, 0) = model.screen
  // Transient boxes are not listed, other tests leave named boxes.
  assert list.all(boxes, fn(box) { box.name != None })
}

pub fn start_a_shell_in_a_transient_copy_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.Listed(Ok([home])))
  let model = press(model, ["enter", "down"])
  assert string.contains(screen(model), "Shell in a transient copy of home")
  let assert tui.Open(_, choices, 1) = model.screen
  let assert [_, tui.Start(True, None)] = choices

  let assert Ok(#(place, tui.InShell(shell:, ..) as thread)) =
    tui.start(context, home, True, None)
  assert place == "a transient copy of home"
  assert shell.box != home.id
  let #(model, _) = tui.update(model, tui.Started(Ok(#(place, thread))))
  // A builtin is chosen by name, then called with two numbers.
  let keys =
    list.flatten([
      ["j", ..string.to_graphemes("int_add")],
      ["enter", "c", "n", "1", "enter", " ", "n", "2", "enter"],
    ])
  let model = press(model, list.take(keys, 4))
  // The name is typed below the code, with the builtins that match.
  assert string.contains(screen(model), "Name int")
  assert string.contains(screen(model), "int_add")
  let model = press(model, list.drop(keys, 4))
  assert string.contains(screen(model), "> !int_add(1, 2)")
  let model = press(model, ["Q"])
  assert model.status == tui.Problem("Nothing is bound to Q")
  let model = press(model, ["enter"])
  let assert tui.Running(waiting: True, log: [tui.Ran(_)], ..) = model.screen
  assert string.contains(screen(model), "waiting")
  let assert Ok(program) = parser.all_from_string("!int_add(1, 2)")
  let program = ir.map_annotation(program, fn(_) { Nil })
  let replied = turn.send(context, shell, turn.Program(program))
  let #(model, _) = tui.update(model, tui.Replied(shell.id, replied))
  assert string.contains(screen(model), "= 3")
}

pub fn chat_in_the_box_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let context =
    Context(..context, llms: dict.from_list([#("test", server.llm(server))]))
  let assert Ok(home) = box.create(context, Some("home"))
  assert tui.choices(context)
    == [
      tui.Start(False, None),
      tui.Start(True, None),
      tui.Start(False, Some("test")),
      tui.Start(True, Some("test")),
    ]
  let assert Ok(#("home", tui.InChat(chat: talk, ..) as thread)) =
    tui.start(context, home, False, Some("test"))
  assert talk.box == home.id
  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.Started(Ok(#("home", thread))))
  assert string.contains(screen(model), "Chat in home")
  let model = press(model, ["h", "i", "enter"])
  let assert Ok(replied) = chat.send(context, talk, "hi")
  let #(model, _) = tui.update(model, tui.Replied(talk.id, Ok(#(replied, []))))
  assert string.contains(screen(model), "you hi")
  assert string.contains(screen(model), "llm hi #1")
}

pub fn create_a_box_test() {
  use context <- helpers.context()
  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.Listed(Ok([])))
  let model = press(model, ["n", ..string.to_graphemes("Bad")])
  assert string.contains(screen(model), "Name of the new box")
  let assert Some(prompt) = model.prompt
  let #(model, _) = tui.update(model, Key("enter"))
  assert None == model.prompt
  let #(model, _) = tui.update(model, prompt.submit(prompt.input))
  assert string.contains(screen(model), "lowercase letters")

  let model = press(model, ["n", ..string.to_graphemes("garden")])
  let assert Some(prompt) = model.prompt
  let #(model, _) = tui.update(model, prompt.submit(prompt.input))
  let #(model, _) = tui.update(model, tui.Listed(box.named(context)))
  assert string.contains(screen(model), "garden")
}
