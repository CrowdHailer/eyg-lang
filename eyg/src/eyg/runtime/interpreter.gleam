import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eygir/expression as e

pub type Term {
  Integer(value: Int)
  Binary(value: String)
  Record(fields: List(#(String, Term)))
  Tagged(label: String, value: Term)
  Function(param: String, body: e.Expression, env: List(#(String, Term)))
  Builtin(func: fn(Term) -> Term)
  Effect(label: String, lift: Term, continuation: fn(Term) -> Term)
}

fn map_values(pairs, f) {
  list.map(
    pairs,
    fn(p) {
      let #(k, v) = p
      #(k, f(v))
    },
  )
}

fn select(label, term) {
  assert Record(fields) = term
  assert Ok(value) = list.key_find(fields, label)
  value
}

fn continue(k, term) {
  k(term)
}

// return just k acc wrap in record call continue outside
fn create_record(fields, env, acc, k) {
  case fields {
    // possibly continue outside
    [] -> continue(k, Record(acc))
    [#(l, exp), ..rest] -> {
      let k = fn(term) { create_record(rest, env, [#(l, term), ..acc], k) }
      eval(exp, env, k)
    }
  }
}

// return just k acc wrap in record call continue outside
fn update_record(fields, env, old, k) {
  case fields {
    [] -> continue(k, Record(old))
    [#(l, exp), ..rest] -> {
      case list.key_pop(old, l) {
        Ok(#(_, old)) -> {
          let k = fn(term) { update_record(rest, env, [#(l, term)], k) }
          eval(exp, env, k)
        }
        Error(_) -> todo("does have the key we need")
      }
      eval(exp, env, k)
    }
  }
}

pub fn branch_find(branches, key) {
  list.find_map(
    branches,
    fn(branch) {
      let #(k, v1, v2) = branch
      case key == k {
        True -> Ok(#(v1, v2))
        False -> Error(Nil)
      }
    },
  )
}

fn match(branches, tail, term, env, k) {
  assert Tagged(label, value) = term
  case branch_find(branches, label) {
    Ok(#(param, then)) -> eval_call(Function(param, then, env), value, k)
    Error(Nil) -> todo
  }
}

pub fn handler_find(handlers, key) {
  list.find_map(
    handlers,
    fn(handler) {
      let #(k, v1, v2, v3) = handler
      case key == k {
        True -> Ok(#(v1, v2, v3))
        False -> Error(Nil)
      }
    },
  )
}

fn eval_effect(term, handlers, svar, state, env, k) {
  case term {
    Effect(label, lift, captured_k) ->
      case handler_find(handlers, label) {
        Ok(#(liftvar, resumevar, then)) -> {
          let resume =
            Builtin(fn(state) {
              Builtin(fn(reply) {
                eval_call(
                  Builtin(captured_k),
                  reply,
                  eval_effect(_, handlers, svar, state, env, k),
                )
              })
            })
          // Think we need some kind of fold generator to execing
          // resumevar needs to be a created function
          let env = [
            #(liftvar, lift),
            #(resumevar, resume),
            #(svar, state),
            ..env
          ]
          eval(then, env, captured_k)
        }
        // if no handler let effect continue to bubble
        _ -> continue(k, term)
      }
    _ -> continue(k, term)
  }
}

fn handle(handlers, svar, state, env, k) {
  // could spilt out arg on fn so that it's always a computation
  // however might well be a variable
  Builtin(fn(comp) {
    eval_call(comp, Record([]), eval_effect(_, handlers, svar, state, env, k))
  })
}

pub fn eval_call(f, arg, k) {
  case f {
    Function(param, body, env) -> {
      let env = [#(param, arg), ..env]
      eval(body, env, k)
    }
    Builtin(f) -> continue(k, f(arg))
    _ -> todo("not a function")
  }
}

// TODO test interpreter, particularly handle
// TODO try moving Handle/Match to key_value lists
pub fn eval(exp: e.Expression, env, k) -> Term {
  case exp {
    e.Lambda(param, body) -> continue(k, Function(param, body, env))
    e.Apply(f, arg) ->
      // io.debug(arg)
      eval(f, env, fn(f) { eval(arg, env, eval_call(f, _, k)) })
    e.Variable(x) ->
      case list.key_find(env, x) {
        Ok(term) -> continue(k, term)
        Error(Nil) -> todo("variable not defined")
      }
    e.Let(var, value, then) ->
      eval(value, env, fn(term) { eval(then, [#(var, term), ..env], k) })
    e.Integer(value) -> continue(k, Integer(value))
    e.Binary(value) -> continue(k, Binary(value))
    e.Vacant -> todo("interpreted a todo")
    e.Record(fields, None) -> create_record(fields, env, [], k)
    e.Record(new, Some(x)) ->
      case list.key_find(env, x) {
        Ok(Record(old)) -> update_record(new, env, old, k)
        Ok(_) -> todo("not a record")
        Error(Nil) -> todo("variable not defined")
      }
    e.Select(label) -> continue(k, Builtin(select(label, _)))
    e.Tag(label) -> continue(k, Builtin(Tagged(label, _)))
    e.Match(branches, tail) ->
      continue(k, Builtin(match(branches, tail, _, env, k)))
    e.Perform(label) -> continue(k, Builtin(Effect(label, _, k)))
    e.Deep(state, branches) ->
      continue(k, Builtin(handle(branches, state, _, env, k)))
    // TODO test
    e.Empty -> continue(k, Record([]))
    e.Extend(label) ->
      continue(
        k,
        Builtin(fn(value) {
          Builtin(fn(record) {
            assert Record(fields) = record
            Record([#(label, value), ..fields])
          })
        }),
      )
    e.Case(label) -> todo("case etsd")
    e.NoCases -> todo("thingk this really should wrror")
  }
}
