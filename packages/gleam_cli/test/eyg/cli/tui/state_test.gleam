import etui/backend
import eyg/analysis/type_/isomorphic as t
import eyg/cli/tui/helpers as h
import eyg/cli/tui/state
import eyg/interpreter/value
import gleam/option.{Some}
import loam/system
import morph/buffer
import morph/repl/history

pub fn exit_in_program_stops_run_test() {
  let #(state, effects) =
    state.init([], h.execute_state())
    |> h.with_code("let x = perform Sleep(200) let x = perform Exit(9) 10")
    |> state.update(state.Input(backend.KeyPress("enter")))
  let assert [system.Wait(200, _resume)] = effects
  let message = state.Task(state.EffectHandled(state.counter - 1, value.unit()))
  let #(state, effects) = state.update(state, message)
  assert [] == effects
  let assert [history.Entry(outcome, effects:, buffer: _)] = state.history
  assert [#("Sleep", #(value.Integer(200), value.unit()))] == effects
  assert history.Aborted("Exited with status 9") == outcome
}

pub fn cancel_program_test() {
  let #(state, effects) =
    state.init([], h.execute_state())
    |> h.with_code("let x = perform Sleep(200) 10")
    |> state.update(state.Input(backend.KeyPress("enter")))
  let assert [system.Wait(200, _resume)] = effects
  let message = state.Input(backend.KeyPress("esc"))
  let #(state, effects) = state.update(state, message)
  assert [] == effects
  let assert [history.Entry(outcome, effects:, buffer: _)] = state.history
  assert [] == effects
  assert history.Aborted("Cancelled") == outcome
}

pub fn cancel_standard_in_returns_error_to_program_test() {
  let #(state, effects) =
    state.init([], h.execute_state())
    |> h.with_code(
      "match perform StandardIn({}) {
        Ok(_) -> { \"unexpected input\" }
        Error(reason) -> { reason }
      }",
    )
    |> state.update(state.Input(backend.KeyPress("enter")))
  assert [] == effects
  let assert state.FreeInput(_, state.ReplyStandardIn(..)) = state.mode

  let #(state, effects) =
    state.update(state, state.Input(backend.KeyPress("esc")))
  assert [] == effects
  assert state.Navigating == state.mode
  let assert [history.Entry(outcome:, effects:, ..)] = state.history
  assert history.Success(Some(value.String("Cancelled"))) == outcome
  assert [
      #("StandardIn", #(value.unit(), value.error(value.String("Cancelled")))),
    ]
    == effects
}

pub fn edits_are_checked_before_returning_to_the_view_test() {
  let initial = state.init([], h.execute_state())
  let assert #(edited, []) =
    state.update(initial, state.Input(backend.Paste("42")))
  assert Ok(t.Integer) == buffer.target_type(edited.buffer)
  let assert #(undone, []) = h.key(edited, "z")
  let assert Some(_) = undone.buffer.analysis
  assert buffer.source(initial.buffer) == buffer.source(undone.buffer)
  let assert #(redone, []) = h.key(undone, "Z")
  assert Ok(t.Integer) == buffer.target_type(redone.buffer)
}

pub fn prompt_input_is_owned_by_the_tui_and_recorded_test() {
  let assert #(state, []) =
    state.init([], h.execute_state())
    |> h.with_code("perform Prompt(\"Name\")")
    |> state.update(state.Input(backend.KeyPress("enter")))
  let assert state.FreeInput(_, state.ReplyPrompt("Name", ..)) = state.mode
  let assert #(state, []) =
    state.update(state, state.Input(backend.Paste("Ada")))
  let assert #(state, []) =
    state.update(state, state.Input(backend.KeyPress("enter")))
  let assert [history.Entry(history.Success(Some(reply)), effects:, ..)] =
    state.history
  assert reply == value.ok(value.String("Ada"))
  assert [#("Prompt", #(value.String("Name"), reply))] == effects
}
