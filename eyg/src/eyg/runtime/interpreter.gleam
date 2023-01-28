import gleam/list
import gleam/map
import gleam/string
import eygir/expression as e

pub type Failure {
  NotAFunction(Term)
  UndefinedVariable(String)
  Vacant
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
    e.Vacant -> Abort(Vacant)
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
    e.Handle(label) -> continue(k, build_runner(label))
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

pub fn handled(label, handler, outer_k, thing) {
  case thing {
    Effect(l, lifted, resume) if l == label -> {
      use partial <- eval_call(handler, lifted)

      use applied <- eval_call(
        partial,
        Builtin(fn(reply, handler_k) {
          handled(label, handler, handler_k, resume(reply))
        }),
      )

      continue(outer_k, applied)
    }
    Value(v) -> continue(outer_k, v)
    // Not equal to this effect
    Effect(l, lifted, resume) ->
      Effect(l, lifted, fn(x) { handled(label, handler, outer_k, resume(x)) })
    Abort(reason) -> Abort(reason)
  }
}

pub fn runner(label, handler) {
  Builtin(fn(exec, k) {
    handled(label, handler, k, eval_call(exec, Record([]), Value))
  })
}

pub fn build_runner(label) {
  Builtin(fn(handler, k) { continue(k, runner(label, handler)) })
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
