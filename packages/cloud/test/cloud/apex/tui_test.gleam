import cloud/apex/context.{Context}
import cloud/apex/tui.{Key}
import cloud/beam/execute
import cloud/box
import cloud/helpers
import cloud/server
import cloud/sessions/event
import cloud/sessions/turn
import etui/buffer
import etui/geometry.{Position}
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/erlang/process
import gleam/http/request
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import unixfs/mfs

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

  let assert Ok(opening) = tui.start(context, home, True, None)
  let assert tui.Opening(place:, session:, chat: False, ..) = opening
  assert place == "a transient copy of home"
  assert session.box != home.id
  let #(model, _) = tui.update(model, tui.Opened(Ok(opening)))
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
  let replied = turn.send(context, session, turn.Program(program))
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
  let assert Ok(opening) = tui.start(context, home, False, Some("test"))
  let assert tui.Opening(place: "home", session:, chat: True, ..) = opening
  assert session.box == home.id
  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.Opened(Ok(opening)))
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

pub fn reopen_a_session_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Ok(tui.Opening(session:, ..)) =
    tui.start(context, home, False, None)
  let assert Ok(_) = turn.send(context, session, turn.Code("!int_add(1, 2)"))

  // Recent sessions include it, other tests leave sessions.
  let #(model, _) = tui.init(context)
  let #(model, _) =
    tui.update(model, tui.RecentListed(False, Ok([#(session, "home")])))
  assert string.contains(screen(model), session.id <> "  in home")

  let #(model, _) = tui.update(model, tui.Opened(tui.open(context, session.id)))
  assert string.contains(screen(model), "!int_add(1, 2)")
  assert string.contains(screen(model), "= 3")
  let assert tui.Running(waiting: False, ..) = model.screen
  assert Error(box.Missing) == tui.open(context, "gone") |> result.replace(Nil)
}

pub fn open_an_unfinished_turn_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let policy = mfs.File(<<context.policy:utf8>>)
  let assert Ok(policy) =
    execute.files(mfs.Put(policy, mfs.Done), context.state)
  // A turn that started and did not finish, as if the process running it stopped.
  let assert Ok(session) =
    turn.create(context, home.id, [], [event.Started("1", policy.cid)])
  let assert Ok(opening) = tui.open(context, session.id)
  let assert tui.Opening(unfinished: True, ..) = opening

  // It is shown waiting, a worker that stops is reported.
  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.Opened(Ok(opening)))
  let assert tui.Running(waiting: True, ..) = model.screen
  let #(model, _) = tui.update(model, tui.Stopped("killed"))
  let assert tui.Running(waiting: False, ..) = model.screen
  assert string.contains(screen(model), "The turn stopped: killed")

  // Opening it finishes the turn.
  let assert Ok(Nil) = turn.resume(context, session)
  let #(model, _) = tui.update(model, tui.Opened(tui.open(context, session.id)))
  assert string.contains(screen(model), "= 1")
}

pub fn show_progress_and_scroll_back_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Ok(opening) = tui.start(context, home, False, None)
  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.Resized(80, 20))
  let #(model, _) = tui.update(model, tui.Opened(Ok(opening)))
  assert 20 == list.length(string.split(screen(model), "\n"))
  let tui.Opening(session:, ..) = opening

  // A reply longer than the screen is shown from its start, the rest is a page down.
  let output =
    list.index_map(list.repeat("line", 40), fn(line, i) {
      line <> " " <> int.to_string(i)
    })
  let model = press(model, ["tab", "1", "enter"])
  let #(model, _) =
    tui.update(model, tui.Replied(session.id, Ok(#(Ok("done"), output))))
  assert string.contains(screen(model), "line 0")
  assert !string.contains(screen(model), "= done")
  assert string.contains(screen(model), "newer lines")
  let model = press(model, ["pagedown", "pagedown", "pagedown"])
  assert string.contains(screen(model), "= done")
  assert string.contains(screen(model), "earlier lines")
  // The wheel scrolls back, and stops at the first line.
  let #(model, _) = tui.update(model, tui.Scrolled(3))
  assert !string.contains(screen(model), "= done")
  let model =
    list.fold(list.repeat(Nil, 30), model, fn(model, _) {
      tui.update(model, tui.Scrolled(3)).0
    })
  assert string.contains(screen(model), "> 1")
  assert !string.contains(screen(model), "earlier lines")
  let #(model, _) = tui.update(model, tui.Scrolled(-300))
  assert string.contains(screen(model), "= done")

  // While a turn runs, what it has done is shown.
  let model = press(model, ["2", "enter"])
  let request =
    request.new() |> request.set_host("example.com") |> request.set_body(<<>>)
  let root = home.root
  let progress =
    tui.progress([
      event.Started("1", root),
      event.Finished(Ok("1"), [], root),
      event.Started("2", root),
      event.Resumed(root),
      event.Requested(request, root),
      event.Slept(10, root),
    ])
  assert progress == ["GET https://example.com", "sleeping 10ms"]
  let #(model, _) =
    tui.update(model, tui.Progressed(session.id, progress, "Partly writ"))
  assert string.contains(screen(model), "· GET https://example.com")
  // The text of a completion is shown as it arrives.
  assert string.contains(screen(model), "llm Partly writ")
}

pub fn transient_sessions_are_hidden_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Ok(tui.Opening(session: shared, ..)) =
    tui.start(context, home, False, None)
  let assert Ok(tui.Opening(session: transient, ..)) =
    tui.start(context, home, True, None)
  let ids = fn(transient) {
    let assert Ok(sessions) = turn.recent(context, 100, transient)
    list.map(sessions, fn(entry) { { entry.0 }.id })
  }
  assert list.contains(ids(False), shared.id)
  assert !list.contains(ids(False), transient.id)
  assert list.contains(ids(True), transient.id)

  let #(model, _) = tui.init(context)
  let #(model, _) = tui.update(model, tui.RecentListed(False, Ok([])))
  assert string.contains(screen(model), "t show transient")
  let #(model, _) = tui.update(model, tui.RecentListed(True, Ok([])))
  assert string.contains(screen(model), "with transient boxes")
}
