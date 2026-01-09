import gleam/option.{None, Some}
import lustre/element/html as h
import website/routes/sign/state.{State}

pub fn model(state) {
  case state {
    State(opener: None, ..) -> Failed(message: "")
    State(..) -> Loading
  }
}

pub type Model {
  Failed(message: String)
  Loading
  Setup
}

pub fn render(state) {
  h.div([], [h.text("sign")])
}
