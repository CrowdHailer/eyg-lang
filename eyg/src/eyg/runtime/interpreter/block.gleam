import eyg/runtime/interpreter/state
import eygir/annotated as a
import gleam/option.{None, Some}

fn loop(next, env) {
  case next {
    state.Loop(state.E(#(a.Vacant(_), _)), e, state.Empty(_)) ->
      Ok(#(None, e.scope))
    state.Loop(state.E(#(_, _)) as c, e, state.Empty(_) as k) ->
      loop(state.step(c, e, k), e.scope)
    state.Loop(c, e, k) -> loop(state.step(c, e, k), env)
    state.Break(Ok(result)) -> Ok(#(Some(result), env))
    state.Break(Error(reason)) -> Error(reason)
  }
}

pub fn execute(exp, env, h) {
  loop(state.step(state.E(exp), env, state.Empty(h)), env.scope)
}

pub fn resume(value, env, k) {
  loop(state.step(state.V(value), env, k), env.scope)
}
