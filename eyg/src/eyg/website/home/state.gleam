import gleam/io
import lustre/effect

pub type State {
  State
}

pub fn init(_) {
  #(State, effect.none())
}

pub fn update(state, message) {
  io.debug(message)
  #(state, effect.none())
}
