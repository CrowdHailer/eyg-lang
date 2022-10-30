import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/option.{None, Option, Some}
import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter as r

pub fn eval(source, env) {
  let #(_, s) = source
  case s {
    e.Binary(value) -> Ok(r.Binary(value))
    e.Tuple(elements) -> {
      try elements = list.try_map(elements, eval(_, env))
      Ok(r.Tuple(elements))
    }
    e.Record(fields) -> {
      try fields = value_try_map(fields, eval(_, env))
      Ok(r.Record(fields))
    }
    e.Access(record, key) -> {
      try record = eval(record, env)
      case record {
        r.Record(fields) ->
          case list.key_find(fields, key) {
            Ok(value) -> Ok(value)
            Error(Nil) -> {
              io.debug(key)
              Error("missing key in record")
            }
          }
        _ -> Error("not a record")
      }
    }
    e.Tagged(tag, value) -> {
      try value = eval(value, env)
      Ok(r.Tagged(tag, value))
    }
    e.Case(value, branches) -> {
      try value = eval(value, env)
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
          eval(then, env)
        }
        Error(Nil) -> Error("missing branch")
      }
    }

    e.Let(pattern, value, then) -> {
      try env = case pattern, value {
        p.Variable(label), #(_, e.Function(pattern, body)) ->
          Ok(map.insert(env, label, r.Function(pattern, body, env, Some(label))))
        _, _ -> {
          try value = eval(value, env)
          r.extend_env(env, pattern, value)
        }
      }
      eval(then, env)
    }
    e.Variable(var) ->
      case map.get(env, var) {
        Ok(value) -> Ok(value)
        Error(Nil) -> Error("missing value")
      }
    e.Function(pattern, body) -> Ok(r.Function(pattern, body, env, None))
    e.Call(func, arg) -> {
      try func = eval(func, env)
      try arg = eval(arg, env)
      exec_call(func, arg)
    }

    e.Hole -> Error("interpreted a program with a hole")
    e.Provider(_, _, generated) ->
      // TODO this could be typed better with an anonymous fn that first unwraps then goes to nil
      eval(dynamic.unsafe_coerce(generated), env)
  }
}

pub fn exec_call(func: r.Object, arg) {
  case func {
    r.Function(pattern, body, captured, self) -> {
      let captured = case self {
        Some(label) -> map.insert(captured, label, func)
        None -> captured
      }
      try inner = r.extend_env(captured, pattern, arg)
      eval(body, inner)
    }
    r.BuiltinFn(func) -> func(arg)
    _ -> todo("Should never be called")
  }
}

fn value_try_map(pairs, func) {
  list.try_map(
    pairs,
    fn(pair) {
      let #(k, v) = pair
      try v = func(v)
      Ok(#(k, v))
    },
  )
}
