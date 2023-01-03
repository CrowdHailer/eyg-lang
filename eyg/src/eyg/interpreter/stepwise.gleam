import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/option.{None, Option, Some}
import gleam/int
import gleam/list
import gleam/map
import gleam/string
import gleam/function
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/codegen/javascript
import eyg/interpreter/interpreter as r
import gleam/javascript as real_js
import gleam/javascript/promise.{Promise}

fn set_key_handler(o) {
  todo("we don't use this but might with key handler as mutable ref")
}

external fn try_catch(fn() -> b) -> Result(b, string) =
  "../../browser_ffi.js" "tryCatch"

external fn do_fetch(String) -> Promise(String) =
  "../../browser_ffi.js" "fetchText"

pub fn eval(source, env) {
  try #(_, _, value) = effect_eval(source, env)
  Ok(value)
}

pub fn effect_eval(source, env) {
  try cont = step(source, env, fn(value) { Ok(Done(value)) })
  loop(cont, [], [])
}

pub fn loop(
  cont: Cont,
  processes,
  messages,
) -> Result(#(List(r.Object), List(r.Object), r.Object), String) {
  case cont {
    Done(value) -> Ok(#(processes, messages, value))
    Cont(value, cont) -> {
      // let #(_, value) = value
      try next = cont(value)
      loop(next, processes, messages)
    }
  }
}

// pub type Cont = Option(fn(r.Object) -> Cont)
pub type Cont {
  Done(r.Object)
  Cont(r.Object, fn(r.Object) -> Result(Cont, String))
}

fn eval_tuple(elements, env, acc, cont) -> Result(Cont, String) {
  case elements {
    [] -> Ok(Cont(r.Tuple(list.reverse(acc)), cont))
    [e, ..elements] ->
      step(
        e,
        env,
        fn(value) { eval_tuple(elements, env, [value, ..acc], cont) },
      )
  }
}

fn eval_record(fields, env, acc, cont) {
  case fields {
    [] -> Ok(Cont(r.Record(list.reverse(acc)), cont))
    [f, ..fields] -> {
      let #(name, e) = f
      step(
        e,
        env,
        fn(value) { eval_record(fields, env, [#(name, value), ..acc], cont) },
      )
    }
  }
}

pub fn step(
  source,
  env,
  cont: fn(r.Object) -> Result(Cont, String),
) -> Result(Cont, String) {
  let #(_, s) = source
  case s {
    e.Binary(content) -> Ok(Cont(r.Binary(content), cont))
    e.Tuple(elements) -> eval_tuple(elements, env, [], cont)
    e.Record(fields) -> eval_record(fields, env, [], cont)
    e.Access(record, key) ->
      step(
        record,
        env,
        fn(value) {
          case value {
            r.Record(fields) ->
              case list.key_find(fields, key) {
                Ok(value) -> Ok(Cont(value, cont))
                _ -> {
                  io.debug(key)
                  Error("missing key in record")
                }
              }
            _ -> Error("not a record")
          }
        },
      )
    e.Tagged(tag, value) ->
      step(value, env, fn(value) { Ok(Cont(r.Tagged(tag, value), cont)) })
    e.Case(value, branches) ->
      step(
        value,
        env,
        fn(value) {
          try #(tag, value) = case value {
            r.Tagged(tag, value) -> Ok(#(tag, value))
            _ -> Error("not a union")
          }
          let match =
            list.find(
              branches,
              fn(branch) {
                let #(t, _, _) = branch
                t == tag
              },
            )
          case match {
            Ok(#(_, pattern, then)) -> {
              try env = r.extend_env(env, pattern, value)
              step(then, env, cont)
            }
            Error(Nil) -> Error("Did not match any branches")
          }
        },
      )
    e.Let(pattern, value, then) ->
      case pattern, value {
        p.Variable(label), #(_, e.Function(pattern, body)) ->
          step(
            then,
            map.insert(env, label, r.Function(pattern, body, env, Some(label))),
            cont,
          )
        _, _ ->
          step(
            value,
            env,
            fn(value) {
              try env = r.extend_env(env, pattern, value)
              step(then, env, cont)
            },
          )
      }
    e.Variable(var) ->
      case map.get(env, var) {
        Ok(value) -> Ok(Cont(value, cont))
        Error(Nil) -> Error("missing value")
      }
    e.Function(pattern, body) ->
      Ok(Cont(r.Function(pattern, body, env, None), cont))
    e.Call(func, arg) ->
      step(
        func,
        env,
        fn(func) { step(arg, env, fn(arg) { step_call(func, arg, cont) }) },
      )

    e.Hole -> Error("interpreted a program with a hole")
    e.Provider(_, _, generated) ->
      // TODO this could be typed better with an anonymous fn that first unwraps then goes to nil
      step(dynamic.unsafe_coerce(generated), env, cont)
  }
  // todo("providers should have been expanded before evaluation")
}

pub fn step_call(func, arg, cont: fn(r.Object) -> Result(Cont, String)) {
  case func {
    r.Function(pattern, body, captured, self) -> {
      let captured = case self {
        Some(label) -> map.insert(captured, label, func)
        None -> captured
      }
      try inner = r.extend_env(captured, pattern, arg)
      step(body, inner, cont)
    }

    r.BuiltinFn(func) -> {
      try value = func(arg)
      Ok(Cont(value, cont))
    }
    _ -> {
      io.debug(func)
      todo("Should never be called")
    }
  }
}
