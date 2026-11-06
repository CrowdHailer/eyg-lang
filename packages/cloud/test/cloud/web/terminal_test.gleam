import cloud/editor
import cloud/sessions
import cloud/shell
import cloud/web/terminal.{Finished, KeyPressed, Pasted}
import gleam/list
import gleam/option.{None, Some}
import morph/editable as e

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
