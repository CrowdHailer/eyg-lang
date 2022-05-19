pub fn bad() {
  fn(state) {
    let state = case Nil {
      _ -> state
    }
    state
  }
}

pub fn good() {
  fn(state) { let state = state }
}
