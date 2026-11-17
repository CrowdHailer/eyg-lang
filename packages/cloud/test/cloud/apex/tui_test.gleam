import cloud/apex/context.{Context}
import cloud/apex/tui.{Key}
import cloud/box
import cloud/helpers
import cloud/server
import cloud/sessions/turn
import etui/buffer
import etui/geometry.{Position}
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
  let assert [_, tui.Start(True, None), tui.ManageSecrets] = choices

  let assert Ok(#(place, session, False)) = tui.start(context, home, True, None)
  assert place == "a transient copy of home"
  assert session.box != home.id
  let #(model, _) = tui.update(model, tui.Started(Ok(#(place, session, False))))
  let keys = string.to_graphemes("!int_add(1, 3") |> list.append(["backspace"])
  let model = press(model, list.append(keys, ["2", ")"]))
  assert string.contains(screen(model), "> !int_add(1, 2)")
  let model = press(model, ["enter"])
  let assert tui.Running(waiting: True, log: [tui.Sent("!int_add(1, 2)")], ..) =
    model.screen
  assert string.contains(screen(model), "waiting")

  let replied = turn.send(context, session, turn.Code("!int_add(1, 2)"))
  let #(model, _) = tui.update(model, tui.Replied(session.id, replied))
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
      tui.ManageSecrets,
    ]
  let assert Ok(#("home", session, True)) =
    tui.start(context, home, False, Some("test"))
  assert session.box == home.id
  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.Started(Ok(#("home", session, True))))
  assert string.contains(screen(model), "Chat in home")
  let model = press(model, ["h", "i", "enter"])
  let replied = turn.send(context, session, turn.Message("hi"))
  let #(model, _) = tui.update(model, tui.Replied(session.id, replied))
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

// Run the work of a prompt as the interface does when it is submitted.
fn submit(model: tui.Model) {
  let assert Some(prompt) = model.prompt
  let #(model, _) = tui.update(model, Key("enter"))
  tui.update(model, prompt.submit(prompt.input)).0
}

pub fn manage_secrets_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.Listed(Ok([home])))
  let model = press(model, ["enter", "down", "down"])
  assert string.contains(screen(model), "Secrets of home")
  let #(model, _) = tui.update(model, tui.SecretsListed(home, Ok([])))
  assert string.contains(screen(model), "No secrets")

  let model = press(model, ["a", ..string.to_graphemes("TOKEN")]) |> submit
  let model = press(model, string.to_graphemes("s3cr3t"))
  // The value is hidden as it is typed.
  assert !string.contains(screen(model), "s3cr3t")
  let model = submit(model)
  assert Ok(dict.from_list([#("TOKEN", "s3cr3t")]))
    == box.secrets(context, home.id)
  assert string.contains(screen(model), "TOKEN")
  assert !string.contains(screen(model), "s3cr3t")
}
