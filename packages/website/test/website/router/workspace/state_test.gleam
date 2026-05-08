import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/option.{Some}
import morph/buffer
import ogre/origin
import website/config
import website/harness/browser
import website/routes/workspace/state.{State}
import website/run

pub fn execute_expression_test() {
  let state = with_source(ir.add(ir.integer(7), ir.integer(21)))
  let assert #(state, []) = command(state, "Enter")
  assert state.Editing == state.mode
  let assert [run.Previous(value:, effects:, ..)] = state.previous
  assert Some(v.Integer(28)) == value
  assert [] == effects
}

pub fn execute_sync_effect_test() {
  let source = ir.call(ir.perform("Random"), [ir.integer(1)])
  let state = with_source(source)
  let assert #(state, []) = command(state, "Enter")
  assert state.Editing == state.mode
  let assert [run.Previous(value:, effects:, ..)] = state.previous
  assert Some(v.Integer(0)) == value
  // TODO keep list of effects
  assert [] == effects
}

pub fn execute_async_effect_test() {
  let source = ir.call(ir.perform("Alert"), [ir.string("Beep")])
  let state = with_source(source)
  let assert #(state, [effect]) = command(state, "Enter")
  let assert state.RunningShell([], run.Handling(0, ..)) = state.mode
  let assert browser.Alert("Beep", resume) = effect
  let assert #(state, []) = state.update(state, resume())

  assert state.Editing == state.mode
  let assert [run.Previous(value:, effects:, ..)] = state.previous
  assert Some(v.unit()) == value
  // TODO keep list of effects
  assert [] == effects
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
