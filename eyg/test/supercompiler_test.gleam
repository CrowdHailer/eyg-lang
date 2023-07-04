import gleam/io
import gleam/list
import gleam/map
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import gleeunit/should
import harness/stdlib

pub type Control {
  E(e.Expression)
  V(r.Term)
  Fn(String, Control, List(#(String, Control)))
}

pub fn step(c, e, k) {
  case c {
    E(e.Variable(v)) -> {
      case list.key_find(e, v) {
        Ok(control) -> K(control, e, k)
        // Need to apply to k or make a value that is something so we don;t loop forever
        Error(Nil) -> k(E(e.Variable(v)), e)
      }
    }

    E(e.Lambda(x, body)) -> {
      K(E(body), e, fn(body, e2) { K(Fn(x, body, e2), e, k) })
    }
    //   case body {
    //     E(exp) -> K(Fn(x, exp, e2), e, k)
    //     V(body) -> K(Fn(x, capture.capture(body), e2), e, k)
    //     Fn(_, _, _) -> todo("closyre")
    //   }
    E(e.Apply(f, a)) ->
      K(
        E(f),
        e,
        fn(f, env) {
          K(
            E(a),
            e,
            fn(a, env) {
              case f {
                Fn(param, body, captured) ->
                  K(body, [#(param, a), ..captured], k)
                V(r.Defunc(r.Builtin(key, applied))) -> {
                  //   let applied =
                  //     list.append(applied, [a])
                  //     |> list.try_map(
                  //       applied,
                  //       fn(c) {
                  //         case c {
                  //           V(value) -> Ok(value)
                  //           // TODO pass in functions
                  //           _ -> Error(Nil)
                  //         }
                  //       },
                  //     )
                  case a {
                    V(a) -> {
                      let assert r.Cont(value, x) =
                        r.call_builtin(
                          key,
                          list.append(applied, [a]),
                          stdlib.env().builtins,
                          r.Value,
                        )
                      let assert r.Value(value) = x(value)
                      //   io.debug(value)
                      //   io.debug(x(value))
                      //   todo("in apply")
                      K(V(value), e, k)
                    }

                    _ -> todo("need to rebuild fn")
                  }
                }
                _ -> {
                  io.debug(f)
                  todo("in apply")
                }
              }
            },
          )
        },
      )

    E(e.Let(label, body, then)) ->
      K(E(body), e, fn(value, env) { K(E(then), [#(label, value), ..env], k) })
    E(e.Binary(value)) -> K(V(r.Binary(value)), e, k)
    E(e.Builtin(identifier)) -> K(V(r.Defunc(r.Builtin(identifier, []))), e, k)

    V(value) -> k(V(value), e)

    // TODO all the applies here
    // Dead code elimination if we look up values
    Fn(param, body, closed) -> k(Fn(param, body, closed), e)
    //   case k {
    //     [] ->
    //       case value {
    //         r.Binary(value) -> Done(e.Binary(value))
    //         _ -> todo("re expression")
    //       }
    //     [k, ..k] -> K(k(value, e), e, k)
    //   }
    _ -> {
      io.debug(#("c---", c))
      todo("supeswer")
    }
  }
  //   todo
}

pub type K {
  Done(e.Expression)
  K(
    Control,
    List(#(String, Control)),
    fn(Control, List(#(String, Control))) -> K,
  )
}

pub fn eval(exp) {
  do_eval(
    E(exp),
    [],
    fn(c, _e) {
      Done(case c {
        E(exp) -> exp
        V(r.Binary(value)) -> e.Binary(value)
        Fn(_, _, _) -> todo("end with fn")
      })
    },
  )
}

fn do_eval(c, e, k) {
  case step(c, e, k) {
    Done(value) -> value
    K(c, e, k) -> do_eval(c, e, k)
  }
}

pub fn supercompiler_test() {
  eval(e.Let("x", e.Binary("hello"), e.Variable("x")))
  |> should.equal(e.Binary("hello"))

  eval(e.Apply(e.Lambda("_", e.Binary("hello")), e.Binary("ignore")))
  |> should.equal(e.Binary("hello"))

  eval(e.Apply(e.Lambda("x", e.Variable("x")), e.Binary("hello")))
  |> should.equal(e.Binary("hello"))

  eval(e.Apply(e.Builtin("string_uppercase"), e.Binary("hello")))
  |> should.equal(e.Binary("HELLO"))
  todo
}
