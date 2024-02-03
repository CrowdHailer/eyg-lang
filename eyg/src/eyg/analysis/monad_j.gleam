// An array represents mutable memory and pointers,
// A list looks like an array
// I can use a JS array but at that point why not use
pub type State {
  State(current_level: Int, current_typevar: Int)
}

fn do(action: fn(State) -> #(State, a), k: fn(a) -> b) -> fn(State) -> b {
  fn(state) {
    let #(state, value) = action(state)
    k(value)
  }
}

fn enter_level() {
  fn(state) { #(State(..state, current_level: state.current_level + 1), Nil) }
}

fn exit_level() {
  fn(state) { #(State(..state, current_level: state.current_level + 1), Nil) }
}

fn return(value) {
  fn(state) { #(state, value) }
}

pub fn infer() {
  use _ <- do(enter_level())
  use _ <- do(enter_level())

  return(1)
}
