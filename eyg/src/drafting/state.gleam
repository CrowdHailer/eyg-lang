import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/effect
import morph/editable as e
import morph/projection
import morph/navigation
import morph/transformation
import drafting/session
import drafting/bindings

pub type Action =
  #(String, fn(projection.Projection) -> State, Option(String))

pub type State {
  State(draft: session.Session)
}

pub fn init(_) {
  #(session.new(bindings.default(), e.Vacant), effect.none())
}

pub fn update(state, message) {
  let assert Ok(session) = session.handle(state, message)
  #(session, effect.none())
}
