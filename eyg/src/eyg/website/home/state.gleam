import lustre/effect

pub type State {
  State
}

pub fn init(_) {
  #(State, effect.none())
}

pub fn update(state, _) {
  #(state, effect.none())
}
