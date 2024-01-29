import scintilla/interpreter/state

pub fn eval(exp, env) {
  loop(state.next(state.eval(exp, env, [])))
}

pub fn exec(statements, env) {
  loop(state.next(state.push_statements(statements, env, [])))
}

pub fn loop(next) {
  case next {
    state.Loop(c, e, k) -> loop(state.step(c, e, k))
    state.Break(result) -> result
  }
}
