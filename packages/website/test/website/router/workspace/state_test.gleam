import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/option.{Some}
import morph/buffer
import morph/picker
import ogre/origin
import pal/system
import website/config
import website/routes/workspace/state.{State}

pub fn execute_expression_test() {
  let state = with_source(ir.add(ir.integer(7), ir.integer(21)))
  let assert #(state, []) = command(state, "Enter")
  assert state.Editing == state.mode
  let assert [state.Previous(value:, effects:, ..)] = state.previous
  assert Some(v.Integer(28)) == value
  assert [] == effects
}

pub fn execute_sync_effect_test() {
  let source = ir.call(ir.perform("Random"), [ir.integer(1)])
  let state = with_source(source)
  let assert #(state, []) = command(state, "Enter")
  assert state.Editing == state.mode
  let assert [state.Previous(value:, effects:, ..)] = state.previous
  assert Some(v.Integer(0)) == value
  // TODO keep list of effects
  assert [] == effects
}

pub fn execute_async_effect_test() {
  let source = ir.call(ir.perform("Alert"), [ir.string("Beep")])
  let state = with_source(source)
  let assert #(state, [effect]) = command(state, "Enter")
  let assert state.RunningShell([], state.Handling(0, ..)) = state.mode
  let assert system.Alert("Beep", resume) = effect
  let assert system.Done(message) = resume()
  let assert #(state, []) = state.update(state, message)

  assert state.Editing == state.mode
  let assert [state.Previous(value:, effects:, ..)] = state.previous
  assert Some(v.unit()) == value
  // TODO keep list of effects
  assert [] == effects
}

pub fn insert_relative_workspace_reference_test() {
  let module = buffer.from_source(ir.integer(42), infer.pure())
  let state = with_source(ir.vacant())
  let modules = dict.from_list([#(#("local", state.EygJson), module)])
  let state = State(..state, modules:)

  let assert #(state, []) = command(state, "q")
  let assert state.Manipulating(..) = state.mode
  let assert #(state, []) =
    state.update(state, state.PickerMessage(picker.Decided("local")))
  let assert #(ir.Reference(ir.Relative(location)), _) =
    buffer.source(state.repl)

  assert "./local.eyg.json" == location
}

pub fn execute_relative_workspace_reference_test() {
  let module = buffer.from_source(ir.integer(42), infer.pure())
  let state = with_source(ir.relative("./local.eyg.json"))
  let modules = dict.from_list([#(#("local", state.EygJson), module)])
  let state = State(..state, modules:)

  let assert #(state, []) = command(state, "Enter")
  let assert [state.Previous(value:, ..)] = state.previous

  assert Some(v.Integer(42)) == value
}

fn command(state, key) {
  state.update(state, state.UserPressedCommandKey(key))
}

fn with_source(source) {
  let assert #(state, [_pull]) = state.init(config())
  State(..state, repl: buffer.from_source(source, repl_context(state)))
}

fn repl_context(_state) {
  // TODO this needs to be the real REPL context
  infer.pure()
}

fn config() {
  config.Config(origin: origin.https("eyg.text"))
}
