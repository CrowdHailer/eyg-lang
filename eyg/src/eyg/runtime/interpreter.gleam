import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eygir/expression as e

// harness global handler world external exterior mount surface
pub fn run(source, env, term, extrinsic) {
  // Probably separate first handle non effectful from second
  handle(eval(source, env, eval_call(_, term, Value(_))), extrinsic)
}

fn handle(return, extrinsic) {
  case return {
    // TODO stateful handler
    Effect(label, term, k) -> handle(k(extrinsic(label, term)), extrinsic)
    Value(term) -> term
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
  Perform(label: String)
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
}

pub fn continue(k, term) {
  case term {
    // Just don't need k on resume
    // Effect(label, lifted) -> {
    //   io.debug(#(label, lifted))
    //   k(Record([]))
    // }
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
    // TODO perform should be effect without arg
    Perform(label) -> Effect(label, arg, k)
    _ -> {
      io.debug(#(f, arg))
      todo("not a function")
    }
  }
}

// TODO try moving Handle/Match to key_value lists
pub fn eval(exp: e.Expression, env, k) {
  case exp {
    e.Lambda(param, body) -> continue(k, Function(param, body, env))
    e.Apply(f, arg) ->
      eval(f, env, fn(f) { eval(arg, env, eval_call(f, _, k)) })
    e.Variable(x) ->
      case list.key_find(env, x) {
        Ok(term) -> continue(k, term)
        Error(Nil) -> {
          io.debug(x)
          todo("variable not defined")
        }
      }
    e.Let(var, value, then) ->
      eval(value, env, fn(term) { eval(then, [#(var, term), ..env], k) })
    e.Integer(value) -> continue(k, Integer(value))
    e.Binary(value) -> continue(k, Binary(value))
    e.Tail -> continue(k, LinkedList([]))
    e.Cons -> continue(k, cons())
    e.Vacant -> todo("interpreted a todo")
    e.Record(fields, _) -> todo("record")
    e.Select(label) -> continue(k, Builtin(select(label)))
    e.Tag(label) ->
      continue(k, Builtin(fn(x, k) { continue(k, Tagged(label, x)) }))
    e.Match(branches, tail) -> todo("match")
    e.Perform(label) -> continue(k, Perform(label))
    e.Deep(state, branches) -> todo("deep")
    e.Empty -> continue(k, Record([]))
    e.Extend(label) -> continue(k, extend(label))
    e.Overwrite(label) -> continue(k, overwrite(label))
    e.Case(label) -> continue(k, match(label))
    e.NoCases -> continue(k, Builtin(fn(_, _) { todo("no cases match") }))
    e.Handle(label) -> continue(k, inner_handle(label))
  }
}

// Test interpreter -> setup node env effects & environment, types and values
//

fn cons() {
  Builtin(fn(value, k) {
    continue(
      k,
      Builtin(fn(tail, k) {
        assert LinkedList(elements) = tail
        continue(k, LinkedList([value, ..elements]))
      }),
    )
  })
}

fn select(label) {
  fn(term, k) {
    assert Record(fields) = term
    assert Ok(value) = list.key_find(fields, label)
    // Value(value)
    continue(k, value)
  }
}

fn extend(label) {
  Builtin(fn(value, k) {
    continue(
      k,
      Builtin(fn(record, k) {
        assert Record(fields) = record
        continue(k, Record([#(label, value), ..fields]))
      }),
    )
  })
}

fn overwrite(label) {
  Builtin(fn(value, k) {
    continue(
      k,
      Builtin(fn(record, k) {
        assert Record(fields) = record
        assert Ok(#(_old, fields)) = list.key_pop(fields, label)
        continue(k, Record([#(label, value), ..fields]))
      }),
    )
  })
}

// which k
fn match(label) {
  Builtin(fn(matched, k) {
    continue(
      k,
      Builtin(fn(otherwise, k) {
        continue(
          k,
          Builtin(fn(value, k) {
            assert Tagged(l, term) = value
            case l == label {
              True -> eval_call(matched, term, k)
              False -> eval_call(otherwise, value, k)
            }
          }),
        )
      }),
    )
  })
}

pub fn inner_handle(label) {
  Builtin(fn(handler, k) {
    let wrapped = fn(term) {
      case continue(k, term) {
        Value(v) -> Value(v)
        Effect(l, lifted, resume) if l == label ->
          eval_call(
            handler,
            lifted,
            eval_call(
              _,
              Builtin(fn(reply, handler_k) {
                case resume(reply) {
                  Value(value) -> continue(handler_k, value)
                  effect -> effect
                }
              }),
              Value,
            ),
          )
        Effect(_, _, _) as other -> other
      }
    }
    continue(wrapped, Function("x", e.Variable("x"), []))
  })
}

// world state
// hGet(state -> key -> kont -> kont(state))(state)(exec)
// Is there a way to pass state through, but if we have fix we don't need to but i need to update inference
// Hmm

pub fn builtin2(f) {
  Builtin(fn(a, k) { continue(k, Builtin(fn(b, k) { f(a, b, k) })) })
}
