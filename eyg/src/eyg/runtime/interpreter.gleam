import gleam/io
import gleam/int
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

pub fn run(source, env, term, extrinsic, expand) {
  case
    eval(
      source,
      env,
      expand,
      fn(f) { handle(eval_call(f, term, expand, Value(_)), extrinsic, expand) },
    )
  {
    // could eval the f and return it by wrapping in a value and then separetly calling eval call in handle
    // Can I have a type called Running, that has a Cont but not Value, and separaetly Return with Value and not Cont
    // The eval fn above could use Not a Function Error in any case which is not a Function
    Value(term) -> Ok(term)
    Abort(failure) -> Error(failure)
    Effect(label, _, _) -> Error(UnhandledEffect(label))
    Cont(_, _) -> todo("should have evaluated and not be a Cont at all")
  }
}

fn handle(return, extrinsic, expand) {
  case return {
    // Don't have stateful handlers because extrinsic handlers can hold references to
    // mutable state db files etc
    Effect(label, term, k) ->
      case map.get(extrinsic, label) {
        Ok(handler) ->
          handle(eval_call(handler, term, expand, k), extrinsic, expand)
        Error(Nil) -> Abort(UnhandledEffect(label))
      }
    Value(term) -> Value(term)
    Cont(term, k) -> handle(k(term), extrinsic, expand)
    Abort(failure) -> Abort(failure)
  }
}

// TODO term and to string in own file
pub type Term {
  Integer(value: Int)
  Binary(value: String)
  LinkedList(elements: List(Term))
  Record(fields: List(#(String, Term)))
  Tagged(label: String, value: Term)
  Function(
    param: String,
    body: e.Expression,
    env: List(#(String, Term)),
    htap: List(Int),
  )
  Builtin(func: fn(Term, fn(Term) -> Return) -> Return)
}

pub fn error(value) {
  Tagged("Error", value)
}

// This might not give in runtime core, more runtime presentation
pub fn to_string(term) {
  case term {
    Integer(value) -> int.to_string(value)
    Binary(value) -> string.concat(["\"", value, "\""])
    LinkedList(items) ->
      list.map(items, to_string)
      |> list.intersperse(", ")
      |> list.prepend("[")
      |> list.append(["]"])
      |> string.concat
    Record(fields) ->
      fields
      |> list.map(field_to_string)
      |> list.intersperse(", ")
      |> list.prepend("{")
      |> list.append(["}"])
      |> string.concat
    Tagged(label, value) -> string.concat([label, "(", to_string(value), ")"])
    Function(param, _, _, _) -> string.concat(["(", param, ") -> ..."])
    Builtin(_) -> "Builtin(...)"
  }
}

fn field_to_string(field) {
  let #(k, v) = field
  string.concat([k, ": ", to_string(v)])
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
  // It's messy to have Value and Cont, but I don't know how to do this in a tail recursive way
  // This problem will hopefully go away as I build a more sophisticated interpreter.
  // Value is needed for returning from eval/run
  // Cont is needed to break the stack (with loop).
  // I could remove Value and always return a result from run, but that would make it not easy to check correct Effects in tests.
  Value(term: Term)
  Cont(term: Term, k: fn(Term) -> Return)

  Effect(label: String, lifted: Term, continuation: fn(Term) -> Return)
  Abort(Failure)
}

// Seemed easer to return Generate than pass expand fn through all steps
// seemend not easier pain around handle of effects vs provider
// Provide(generator: Term, htap: List(Int), k: fn(Term) -> Return)

pub fn continue(k, term) {
  Cont(term, k)
}

pub fn eval_call(f, arg, expand, k) {
  loop(step_call(f, arg, expand, k))
}

fn step_call(f, arg, expand, k) {
  case f {
    Function(param, body, env, htap) -> {
      let env = [#(param, arg), ..env]
      step(body, env, expand, [0, ..htap], k)
    }
    // builtin needs to return result for the case statement
    Builtin(f) -> f(arg, k)
    term -> Abort(NotAFunction(term))
  }
}

// Loop is always tail recursive.
// It is used to string individual steps into an eval call.
// If not separated the eval implementation causes stack overflows.
// This is because eval needs references to itself in continuations.
pub fn loop(return) {
  case return {
    Cont(term, k) -> loop(k(term))
    return -> return
  }
}

// eval_at if need path
pub fn eval(exp: e.Expression, env, expand, k) {
  loop(step(exp, env, expand, [], k))
}

fn step(exp: e.Expression, env, expand, htap, k) {
  case exp {
    e.Lambda(param, body) -> continue(k, Function(param, body, env, htap))
    e.Apply(f, arg) ->
      step(
        f,
        env,
        expand,
        [0, ..htap],
        fn(f) {
          step(arg, env, expand, [1, ..htap], step_call(f, _, expand, k))
        },
      )
    e.Variable(x) ->
      case list.key_find(env, x) {
        Ok(term) -> continue(k, term)
        Error(Nil) -> Abort(UndefinedVariable(x))
      }
    e.Let(var, value, then) ->
      step(
        value,
        env,
        expand,
        [0, ..htap],
        fn(term) { step(then, [#(var, term), ..env], expand, [1, ..htap], k) },
      )
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
    e.Case(label) -> continue(k, match(label, expand))
    e.NoCases -> continue(k, Builtin(fn(_, _) { Abort(NoCases) }))
    e.Handle(label) -> continue(k, build_runner(label, expand))
    e.Provider(generator) ->
      step(generator, env, expand, [0, ..htap], expand(_, htap, k))
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

fn match(label, expand) {
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
                  True -> step_call(matched, term, expand, k)
                  False -> step_call(otherwise, value, expand, k)
                }
              term -> Abort(IncorrectTerm("Tagged", term))
            }
          }),
        )
      }),
    )
  })
}

pub fn handled(label, handler, outer_k, thing, expand) {
  case thing {
    Effect(l, lifted, resume) if l == label -> {
      use partial <- step_call(handler, lifted, expand)

      use applied <- step_call(
        partial,
        Builtin(fn(reply, handler_k) {
          handled(label, handler, handler_k, loop(resume(reply)), expand)
        }),
        expand,
      )

      continue(outer_k, applied)
    }
    Value(v) -> continue(outer_k, v)
    Cont(term, k) -> Cont(term, k)
    // Not equal to this effect
    Effect(l, lifted, resume) ->
      Effect(
        l,
        lifted,
        fn(x) { handled(label, handler, outer_k, loop(resume(x)), expand) },
      )
    Abort(reason) -> Abort(reason)
  }
}

pub fn runner(label, handler, expand) {
  Builtin(fn(exec, k) {
    handled(
      label,
      handler,
      k,
      eval_call(exec, Record([]), expand, Value),
      expand,
    )
  })
}

pub fn build_runner(label, expand) {
  Builtin(fn(handler, k) { continue(k, runner(label, handler, expand)) })
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
// pub fn provider(generator) {
//   io.debug(#("generator", generator))
//   // I could return a lazy value but would need to reverse everything i.e. turn runtime value into thing
//   // It's not necessary to have provider return a function
//   // could pass lazy value to everything but would also get executed more than once because when
//   // pulling a record field we only know its a type of at least that value and we don't know what to pass inside
//   Builtin(fn(func, k) {
//     io.debug(func)
//     // io.debug(type_)
//     todo("error should be expanded OR can I take type from runtime")
//   })
// }
// // Path information in interpreter which is available to provider
