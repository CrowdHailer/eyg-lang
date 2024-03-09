import lustre/effect

pub type State {
  State(content: String)
}

pub fn init(_) {
  #(State("hello"), effect.none())
}

pub type TextInput {
  TextInput(String)
}

pub fn update(_state, message) {
  case message {
    TextInput(content) -> #(State(content: content), effect.none())
  }
}
