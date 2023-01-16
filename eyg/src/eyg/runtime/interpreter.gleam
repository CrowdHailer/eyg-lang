import gleam/io
import gleam/list
import gleam/map
import gleam/string
import eygir/expression as e

pub type Failure {
  NotAFunction(Term)
  UndefinedVariable(String)
  Todo
  NoCases
  UnhandledEffect(String)
  IncorrectTerm(expected: String, got: Term)
  MissingField(String)
}

// TODO run test where handlers are applied only on call, assume closed always for initial inference
// harness global handler world external exterior mount surface
pub fn run(source, env, term, extrinsic) {
  // Probably separate first handle non effectful from second
  handle(eval(source, env, eval_call(_, term, Value(_))), extrinsic)
}

fn handle(return, extrinsic) {
  case return {
    // Don't have stateful handlers because extrinsic handlers can hold references to
    // mutable state db files etc
    Effect(label, term, k) ->
      case map.get(extrinsic, label) {
        Ok(handler) -> handle(eval_call(handler, term, k), extrinsic)
        Error(Nil) -> Error(UnhandledEffect(label))
      }
    Value(term) -> Ok(term)
    Abort(failure) -> Error(failure)
  }
}

pub type Term {
  Integer(value: Int)
  Binary(value: String)
  LinkedList(elements: List(Term))
  Record(fields: List(#(String, Term)))
  Tagged(label: String, value: Term)
  Function(param: String, body: e.Expression, env: List(#(String, Term)))
  Builtin(func: fn(Term, fn(Term) -> Return) -> Return)
}

pub fn field(term, field) {
  case term {
    Record(fields) ->
      case list.key_find(fields, field) {
        Ok(value) -> Ok(value)
        Error(Nil) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

pub type Return {
  Value(term: Term)
  Effect(label: String, lifted: Term, continuation: fn(Term) -> Return)
  Abort(Failure)
}

pub fn continue(k, term) {
  case term {
    _ -> k(term)
  }
}

pub fn eval_call(f, arg, k) {
  case f {
    Function(param, body, env) -> {
      let env = [#(param, arg), ..env]
      eval(body, env, k)
    }
    // builtin needs to return result for the case statement
    Builtin(f) -> f(arg, k)
    term -> Abort(NotAFunction(term))
  }
}

pub fn eval(exp: e.Expression, env, k) {
  case exp {
    e.Lambda(param, body) -> continue(k, Function(param, body, env))
    e.Apply(f, arg) ->
      eval(f, env, fn(f) { eval(arg, env, eval_call(f, _, k)) })
    e.Variable(x) ->
      case list.key_find(env, x) {
        Ok(term) -> continue(k, term)
        Error(Nil) -> Abort(UndefinedVariable(x))
      }
    e.Let(var, value, then) ->
      eval(value, env, fn(term) { eval(then, [#(var, term), ..env], k) })
    e.Integer(value) -> continue(k, Integer(value))
    e.Binary(value) -> continue(k, Binary(value))
    e.Tail -> continue(k, LinkedList([]))
    e.Cons -> continue(k, cons())
    e.Vacant -> Abort(Todo)
    e.Select(label) -> continue(k, Builtin(select(label)))
    e.Tag(label) ->
      continue(k, Builtin(fn(x, k) { continue(k, Tagged(label, x)) }))
    e.Perform(label) ->
      continue(k, Builtin(fn(lift, resume) { Effect(label, lift, resume) }))
    e.Empty -> continue(k, Record([]))
    e.Extend(label) -> continue(k, extend(label))
    e.Overwrite(label) -> continue(k, overwrite(label))
    e.Case(label) -> continue(k, match(label))
    e.NoCases -> continue(k, Builtin(fn(_, _) { Abort(NoCases) }))
    e.Handle(label) -> continue(k, inner_handle(label))
  }
}

fn cons() {
  Builtin(fn(value, k) {
    continue(
      k,
      Builtin(fn(tail, k) {
        case tail {
          LinkedList(elements) -> continue(k, LinkedList([value, ..elements]))
          term -> Abort(IncorrectTerm("LinkedList", term))
        }
      }),
    )
  })
}

fn select(label) {
  fn(term, k) {
    case term {
      Record(fields) ->
        case list.key_find(fields, label) {
          Ok(value) -> continue(k, value)
          Error(Nil) -> Abort(MissingField(label))
        }
      term -> Abort(IncorrectTerm(string.append("Record -select", label), term))
    }
  }
}

fn extend(label) {
  Builtin(fn(value, k) {
    continue(
      k,
      Builtin(fn(term, k) {
        case term {
          Record(fields) -> continue(k, Record([#(label, value), ..fields]))
          term -> Abort(IncorrectTerm("Record -extend", term))
        }
      }),
    )
  })
}

fn overwrite(label) {
  Builtin(fn(value, k) {
    continue(
      k,
      Builtin(fn(term, k) {
        case term {
          Record(fields) ->
            case list.key_pop(fields, label) {
              Ok(#(_old, fields)) ->
                continue(k, Record([#(label, value), ..fields]))
              Error(Nil) -> Abort(MissingField(label))
            }
          term -> Abort(IncorrectTerm("Record -overwrite", term))
        }
      }),
    )
  })
}

fn match(label) {
  Builtin(fn(matched, k) {
    continue(
      k,
      Builtin(fn(otherwise, k) {
        continue(
          k,
          Builtin(fn(value, k) {
            case value {
              Tagged(l, term) ->
                case l == label {
                  True -> eval_call(matched, term, k)
                  False -> eval_call(otherwise, value, k)
                }
              term -> Abort(IncorrectTerm("Tagged", term))
            }
          }),
        )
      }),
    )
  })
}

fn handled(label, handler, k) {
  fn(term) {
    io.debug(term)
    // always exec
    case continue(k, term) {
      Effect(l, lifted, resume) if l == label -> {
        io.debug(#("eff", l, lifted))
        eval_call(
          handler,
          lifted,
          eval_call(
            _,
            Builtin(fn(reply, handler_k) {
              case continue(handled(label, handler, resume), reply) {
                Value(v) -> {
                  io.debug(#("foo", v))
                  // continue(handler_k, v)
                  Value(v)
                }
                other -> other
              }
            }),
            Value,
          ),
        )
      }
      // TODO need to unwrap continuation
      other -> {
        io.debug(#("other", other))
        other
      }
    }
  }
}

pub fn do(label, handler, k, thing) {
  case thing {
    Effect(l, lifted, resume) if l == label ->
      eval_call(
        handler,
        lifted,
        eval_call(
          _,
          Builtin(fn(reply, handler_k) {
            io.debug(#("tiddle"))
            // todo("inners")
            do(label, handler, handler_k, resume(reply))
          }),
          // eval_call(resume, reply, Value)
          Value,
        ),
      )
      |> io.debug
    // todo("runner")
    Value(v) -> continue(k, v)
    other -> other
  }
}

// Is it easier without multiple resumption?
pub fn runner(label, handler) {
  Builtin(fn(exec, k) {
    do(label, handler, k, eval_call(exec, Record([]), Value))
  })
  // case eval_call(exec, Record([]), Value) {
  //   Effect(l, lifted, resume) if l == label ->
  //     eval_call(
  //       handler,
  //       lifted,
  //       eval_call(
  //         _,
  //         Builtin(fn(reply, handler_k) {
  //           io.debug(#("tiddle"))
  //           // todo("inners")
  //           case resume(reply) {
  //             Value(v) -> continue(handler_k, v)
  //             // There seems to be value in a try continue
  //             other -> {
  //               io.debug(#("other", other))
  //               other
  //             }
  //           }
  //         }),
  //         // eval_call(resume, reply, Value)
  //         Value,
  //       ),
  //     )
  //     |> io.debug
  //   // todo("runner")
  //   Value(v) -> continue(k, v)
  //   other -> other
  // }
}

pub fn inner_handle(label) {
  Builtin(fn(handler, k) {
    // let wrapped = handled(label, handler, k)
    continue(k, runner(label, handler))
  })
}

pub fn builtin2(f) {
  Builtin(fn(a, k) { continue(k, Builtin(fn(b, k) { f(a, b, k) })) })
}

pub fn builtin3(f) {
  Builtin(fn(a, k) {
    continue(
      k,
      Builtin(fn(b, k) { continue(k, Builtin(fn(c, k) { f(a, b, c, k) })) }),
    )
  })
}
