import gleam/io
import gleam/dict
import gleam/option.{None}
import morph/editable as e
import morph/projection
import spotless/state
import eyg/runtime/interpreter/state as other_state
import gleeunit/should

// Copy effect
// Need Promise type
//
// TODO why is inference called contextual
// TODO check that all effects are type checked
// Can I gather all the definitions of effects together -> is capabilities a better name

pub fn error_test() {
  let src = e.Call(e.Perform("Log"), [e.String("")])
  let p = projection.focus_at(src, [], [])
  // io.debug(e.to_expression(src))
  state.type_errors(
    p,
    // TODO I don't think we use this env
    other_state.Env([], dict.new()),
  )
  |> should.equal([])
}
