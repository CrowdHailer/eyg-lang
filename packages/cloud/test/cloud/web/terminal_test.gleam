import cloud/editor
import cloud/fs
import cloud/sessions
import cloud/shell
import cloud/web/terminal.{Dropped, Finished, KeyPressed, Pasted}
import eyg/ir/tree as ir
import gleam/list
import gleam/option.{None, Some}
import morph/buffer
import morph/editable as e
import multiformats/cid/v1

fn setup() {
  let assert Ok(registry) = sessions.start()
  terminal.new(registry, sessions.create(registry))
}

fn keys(model, keys) {
  list.fold(keys, model, fn(model, key) {
    let #(model, _effect) = terminal.update(model, KeyPressed(key))
    model
  })
}

/// Deliver the result of the running command, as its worker would.
fn finish(model: terminal.Model) {
  let assert Some(running) = model.running
  let #(output, snapshot) =
    shell.run(
      sessions.store(model.sessions),
      running.source,
      sessions.current(model.session),
    )
  let #(model, _) =
    terminal.update(model, Finished(running.id, output, snapshot))
  model
}

fn paste(model, text) {
  let #(model, _) = terminal.update(model, Pasted(text))
  model
}

pub fn build_and_run_an_integer_test() {
  let model = setup() |> keys(["n", "4", "2", "enter"])
  assert editor.expression(model.editor) == e.Integer(42)
  let model = keys(model, ["enter"])
  let assert Some(running) = model.running
  assert running.source == e.Integer(42)
  assert editor.is_empty(model.editor)
  let model = finish(model)
  assert model.running == None
  let assert Ok(last) = list.last(model.session.steps)
  assert last.output == [shell.Result("42")]
}

pub fn paste_source_test() {
  let model = setup() |> paste("!int_add(1, 2)") |> keys(["enter"]) |> finish
  let assert Ok(last) = list.last(model.session.steps)
  assert last.output == [shell.Result("3")]
}

pub fn paste_error_is_shown_test() {
  let model = setup() |> paste("let = 1")
  let assert Some(_) = model.editor.message
  assert editor.is_empty(model.editor)
}

pub fn enter_on_empty_draft_does_not_run_test() {
  let model = setup() |> keys(["enter"])
  assert model.running == None
  let assert Some(_) = model.editor.message
}

pub fn variables_are_typed_from_scope_test() {
  let model =
    setup() |> paste("let x = 1") |> keys(["enter"]) |> finish |> paste("x")
  let assert Some(_) = model.editor.buffer.analysis
}

pub fn help_toggles_test() {
  let model = setup() |> keys(["?"])
  assert model.help
  assert !keys(model, ["?"]).help
}

pub fn recall_earlier_commands_test() {
  let model =
    setup()
    |> paste("1")
    |> keys(["enter"])
    |> finish
    |> paste("2")
    |> keys(["enter"])
    |> finish
  let model = keys(model, ["up"])
  assert editor.expression(model.editor) == e.Integer(2)
  let model = keys(model, ["up"])
  assert editor.expression(model.editor) == e.Integer(1)
  let model = keys(model, ["down"])
  assert editor.expression(model.editor) == e.Integer(2)
  let model = keys(model, ["down"])
  assert editor.is_empty(model.editor)
}

pub fn escape_interrupts_test() {
  let model = setup() |> paste("1") |> keys(["enter", "esc"])
  assert model.running == None
  let assert Ok(last) = list.last(model.session.steps)
  assert last.output == [shell.Failure("interrupted")]
}

pub fn keys_are_ignored_while_running_test() {
  let model = setup() |> paste("1") |> keys(["enter"])
  let after = keys(model, ["n", "?"])
  assert after == model
}

pub fn key_name_test() {
  let name = fn(key, ctrl, alt, shift) {
    terminal.key_name(key, ctrl:, alt:, shift:)
  }
  assert name("ArrowLeft", False, False, False) == Ok("left")
  assert name("Enter", False, False, False) == Ok("enter")
  assert name("Escape", False, False, False) == Ok("esc")
  assert name("E", False, False, True) == Ok("E")
  assert name("a", True, False, False) == Ok("ctrl+a")
  assert name(" ", False, False, False) == Ok(" ")
  assert name("Tab", False, False, True) == Ok("backtab")
  assert name("Shift", False, False, True) == Error(Nil)
}

pub fn import_a_file_from_the_file_system_test() {
  let model =
    setup()
    |> paste(
      "perform WriteFile({path: \"lib.eyg\", contents: !string_to_binary(\"!int_add(40, 2)\")})",
    )
    |> keys(["enter"])
    |> finish
  assert model.editor.files == ["lib.eyg"]
  let model = keys(model, ["q", "l", "tab", "enter"])
  assert editor.expression(model.editor) == e.Reference(ir.Relative("lib.eyg"))
  // The import is type checked from the file.
  assert buffer.block_errors(model.editor.buffer) == []
  let model = keys(model, ["enter"]) |> finish
  let assert Ok(last) = list.last(model.session.steps)
  assert last.output == [shell.Result("42")]
}

pub fn import_needs_an_existing_file_test() {
  let model = setup() |> keys(["q", "x", "enter"])
  let assert editor.Importing(..) = model.editor.mode
}

fn upload(model: terminal.Model, files) {
  let store = sessions.store(model.sessions)
  let root =
    list.fold(files, fs.empty(store), fn(root, file) {
      let #(path, contents) = file
      let assert Ok(root) = fs.write_file(store, root, path, contents)
      root
    })
  let #(model, _) = terminal.update(model, Dropped(v1.to_string(root)))
  model
}

pub fn mount_dropped_files_test() {
  let model = setup() |> upload([#("project/a.txt", <<"a">>)])
  let assert Some(mounting) = model.mounting
  assert mounting.names == ["project"]
  let model = keys(model, ["backspace", "/", "w", "enter"])
  assert model.mounting == None
  let assert Ok(last) = list.last(model.session.steps)
  assert last.command == sessions.Mount("/w", ["project"])
  let store = sessions.store(model.sessions)
  assert fs.read_file(store, last.snapshot.root, "/w/project/a.txt")
    == Ok(<<"a">>)
  // Mounted files can be imported.
  assert model.editor.files == ["w/project/a.txt"]
}

pub fn mount_does_not_replace_test() {
  let model =
    setup()
    |> upload([#("a.txt", <<"a">>)])
    |> keys(["enter"])
    |> upload([#("a.txt", <<"b">>)])
    |> keys(["enter"])
  let assert Some(mounting) = model.mounting
  assert mounting.box.error == Some("a.txt already exists in /")
  let model = keys(model, ["esc"])
  assert model.mounting == None
  assert sessions.commands(model.session) == 1
}

pub fn recall_skips_mounts_test() {
  let model =
    setup()
    |> paste("1")
    |> keys(["enter"])
    |> finish
    |> upload([#("a.txt", <<"a">>)])
    |> keys(["enter", "up"])
  assert editor.expression(model.editor) == e.Integer(1)
}
