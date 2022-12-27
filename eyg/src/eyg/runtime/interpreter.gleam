import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eygir/expression as e

// harness global handler world external exterior mount surface
pub fn run(source, term, extrinsic) {
  handle(eval(source, [], eval_call(_, term, Value(_))), extrinsic)
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
  Record(fields: List(#(String, Term)))
  Tagged(label: String, value: Term)
  Function(param: String, body: e.Expression, env: List(#(String, Term)))
  Builtin(func: fn(Term) -> Return)
  Perform(label: String)
}

pub type Return {
  Value(term: Term)
  Effect(label: String, lifted: Term, continuation: fn(Term) -> Return)
}

fn continue(k, term) {
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
    Builtin(f) ->
      case f(arg) {
        Value(term) -> continue(k, term)
        Effect(l, a, _gnore) -> Effect(l, a, k)
      }
    // TODO perform should be effect without arg
    Perform(label) -> Effect(label, arg, k)
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
    e.Tag(label) -> continue(k, Builtin(fn(x) { Value(Tagged(label, x)) }))
    e.Match(branches, tail) -> todo("match")
    e.Perform(label) -> continue(k, Perform(label))
    e.Deep(state, branches) -> todo("deep")
    // TODO test
    e.Empty -> continue(k, Record([]))
    e.Extend(label) -> continue(k, extend(label))
    e.Case(label) -> continue(k, match(label))
    e.NoCases -> continue(k, Builtin(fn(_) { todo("no cases match") }))
  }
}

// Test interpreter -> setup node env effects & environment, types and values
//
// fn builtin2(f) {
//   Builtin(fn(a) { Builtin(fn(b) { f(a, b) }) })
// }

fn select(label, term) {
  assert Record(fields) = term
  assert Ok(value) = list.key_find(fields, label)
  Value(value)
}

fn extend(label) {
  Builtin(fn(value) {
    Value(Builtin(fn(record) {
      assert Record(fields) = record
      Value(Record([#(label, value), ..fields]))
    }))
  })
}

// which k
fn match(label) {
  Builtin(fn(matched) {
    Value(Builtin(fn(otherwise) {
      Value(Builtin(fn(value) {
        assert Tagged(l, term) = value
        case l == label {
          True -> eval_call(matched, term, Value)
          False -> eval_call(otherwise, value, Value)
        }
      }))
    }))
  })
}
