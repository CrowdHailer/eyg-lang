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
  Effect(label: String, lift: Term)
}

fn continue(k, term) {
  case term {
    // Just don't need k on resume
    Effect(label, lifted) -> {
      io.debug(#(label, lifted))
      k(Record([]))
    }
    _ -> k(term)
  }
}

pub fn eval_call(f, arg, k) {
  case f {
    Function(param, body, env) -> {
      let env = [#(param, arg), ..env]
      eval(body, env, k)
    }
    Builtin(f) -> continue(k, f(arg))
    _ -> {
      io.debug(#(f, arg))
      todo("not a function")
    }
  }
}

// TODO test interpreter, particularly handle
// TODO try moving Handle/Match to key_value lists
pub fn eval(exp: e.Expression, env, k) {
  case exp {
    e.Lambda(param, body) -> continue(k, Function(param, body, env))
    e.Apply(f, arg) -> {
      1
      // io.debug(arg)
      eval(f, env, fn(f) { eval(arg, env, eval_call(f, _, k)) })
    }
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
    e.Record(fields, _) -> todo("record")
    e.Select(label) -> continue(k, Builtin(select(label, _)))
    e.Tag(label) -> continue(k, Builtin(Tagged(label, _)))
    e.Match(branches, tail) -> todo("match")
    e.Perform(label) -> continue(k, Builtin(Effect(label, _)))
    e.Deep(state, branches) -> todo("deep")
    // TODO test
    e.Empty -> continue(k, Record([]))
    e.Extend(label) -> continue(k, extend(label))
    e.Case(label) -> todo("case etsd")
    e.NoCases -> todo("thingk this really should wrror")
  }
}

// Test interpreter -> setup node env effects & environment, types and values
//
fn builtin2(f) {
  Builtin(fn(a) { Builtin(fn(b) { f(a, b) }) })
}

fn select(label, term) {
  assert Record(fields) = term
  assert Ok(value) = list.key_find(fields, label)
  value
}

fn extend(label) {
  Builtin(fn(value) {
    Builtin(fn(record) {
      assert Record(fields) = record
      Record([#(label, value), ..fields])
    })
  })
}
