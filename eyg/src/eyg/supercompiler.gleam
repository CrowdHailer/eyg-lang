import gleam/io
import gleam/list
import gleam/map
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import harness/stdlib

pub type Control {
  E(e.Expression)
  V(r.Term)
  Fn(String, Control, List(#(String, Control)))
}

pub type K {
  Done(e.Expression)
  K(
    Control,
    List(#(String, Control)),
    fn(Control, List(#(String, Control))) -> K,
  )
}

pub fn step(control, env, k) {
  case control {
    E(e.Variable(var)) -> {
      case list.key_find(env, var) {
        Ok(control) -> K(control, env, k)
        // Need to apply to k or make a value that is something so we don;t loop forever
        Error(Nil) -> k(E(e.Variable(var)), env)
      }
    }
    E(e.Lambda(param, body)) -> {
      use body, env2 <- K(E(body), env)
      K(Fn(param, body, env2), env, k)
    }
    E(e.Apply(func, arg)) -> {
      use func, env <- K(E(func), env)
      use arg, env <- K(E(arg), env)
      case func {
        Fn(param, body, captured) -> K(body, [#(param, arg), ..captured], k)
        V(r.Defunc(r.Builtin(key, applied))) -> {
          case arg {
            V(arg) -> {
              let assert r.Cont(value, x) =
                r.call_builtin(
                  key,
                  list.append(applied, [arg]),
                  stdlib.env().builtins,
                  r.Value,
                )
              let assert r.Value(value) = x(value)
              //   io.debug(value)
              //   io.debug(x(value))
              //   todo("in apply")
              K(V(value), env, k)
            }

            _ -> todo("need to rebuild fn")
          }
        }
        _ -> {
          io.debug(func)
          todo("in apply")
        }
      }
    }
    E(e.Let(label, body, then)) -> {
      use value, env <- K(E(body), env)
      K(E(then), [#(label, value), ..env], k)
    }
    E(e.Binary(value)) -> K(V(r.Binary(value)), env, k)
    E(e.Builtin(identifier)) ->
      K(V(r.Defunc(r.Builtin(identifier, []))), env, k)

    V(value) -> k(V(value), env)

    Fn(param, body, closed) -> k(Fn(param, body, closed), env)
    _ -> {
      io.debug(#("control---", control))
      todo("supeswer")
    }
  }
}


pub fn eval(exp) {
  do_eval(
    E(exp),
    [],
    fn(control, _e) {
      Done(case control {
        E(exp) -> exp
        V(r.Binary(value)) -> e.Binary(value)
        Fn(_, _, _) -> todo("end with fn")
      })
    },
  )
}

fn do_eval(control, e, k) {
  case step(control, e, k) {
    Done(value) -> value
    K(control, e, k) -> do_eval(control, e, k)
  }
}
