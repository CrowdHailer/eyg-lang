import gleam/dict
import type_systems/w_test as w

pub type StateResult(state, value, reason) =
  fn(state) -> Result(#(state, value), reason)

pub fn ok(value) -> StateResult(_, _, _) {
  fn(current) { Ok(#(current, value)) }
}

pub fn stop(reason) -> StateResult(_, _, _) {
  fn(_current) { Error(reason) }
}

pub fn bind(m, then) -> StateResult(_, _, _) {
  fn(state) {
    case m(state) {
      Ok(#(next, value)) -> then(value)(next)
      Error(reason) -> Error(reason)
    }
  }
}

pub fn instantiate(s) {
  todo
}

// get/put
pub fn j(env, exp) {
  case exp {
    w.Var(x) ->
      case dict.get(env, x) {
        Ok(scheme) -> ok(instantiate(scheme))
        Error(Nil) -> stop(todo)
      }
    w.App(e1, e2) -> {
      use t1 <- bind(j(env, e1))
      use t2 <- bind(j(env, e2))
      use beta <- fresh()
      use Nil <- bind(unify(t1, t2))
      ok(beta)
    }
    w.Abs(x, e) -> {
      use beta <- fresh()
      let env = dict.insert(env, x, Scheme([], beta))
      use t <- bind(j(env, e))
      ok(w.TFun(beta, t))
    }
    w.Let(x, e1, e2) -> {
      use t1 <- bind(j(env, e1))
      let scheme = todo as "generalize"
      j(dict.insert(env, x, scheme), e2)
    }
    w.Constant(w.Integer) -> ok(w.TPrimitive(w.Integer))
  }
}
