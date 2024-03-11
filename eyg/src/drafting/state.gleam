import lustre/effect
import morph/editable as e
import drafting/session
import drafting/bindings

pub type State {
  State(draft: session.Session)
}

pub fn init(_) {
  #(session.new(bindings.default(), e.Vacant), effect.none())
}

pub fn update(state, message) {
  let assert Ok(session) = session.handle(state, message, fn() { [] })
  #(session, effect.none())
}
