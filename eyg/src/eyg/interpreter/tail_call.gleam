import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/option.{None, Option, Some}
import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/codegen/javascript
import eyg/interpreter/interpreter as r

fn eval_tuple(elements, env, acc, cont) {
  case elements {
    [] -> cont(r.Tuple(list.reverse(acc)))
    [e, ..elements] ->
      do_eval(
        e,
        env,
        fn(value) { eval_tuple(elements, env, [value, ..acc], cont) },
      )
  }
}

fn exec_record(fields, env, acc, cont) {
  case fields {
    [] -> cont(r.Record(list.reverse(acc)))
    [f, ..fields] -> {
      let #(name, e) = f
      do_eval(
        e,
        env,
        fn(value) { exec_record(fields, env, [#(name, value), ..acc], cont) },
      )
    }
  }
}

pub fn eval(source, env) {
  do_eval(source, env, fn(x) { Ok(x) })
}

pub fn do_eval(source, env, cont) -> Result(r.Object, String) {
  let #(_, s) = source
  case s {
    e.Binary(content) -> cont(r.Binary(content))
    e.Tuple(elements) -> eval_tuple(elements, env, [], cont)
    e.Record(fields) -> exec_record(fields, env, [], cont)
    e.Access(record, key) ->
      do_eval(
        record,
        env,
        fn(value) {
          case value {
            r.Record(fields) ->
              case list.key_find(fields, key) {
                Ok(value) -> cont(value)
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
      do_eval(value, env, fn(value) { cont(r.Tagged(tag, value)) })
    e.Case(value, branches) ->
      do_eval(
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
              do_eval(then, env, cont)
            }
            Error(Nil) -> Error("Did not match any branches")
          }
        },
      )
    e.Let(pattern, value, then) ->
      case pattern, value {
        p.Variable(label), #(_, e.Function(pattern, body)) ->
          do_eval(
            then,
            map.insert(env, label, r.Function(pattern, body, env, Some(label))),
            cont,
          )
        _, _ ->
          do_eval(
            value,
            env,
            fn(value) {
              try env = r.extend_env(env, pattern, value)
              do_eval(then, env, cont)
            },
          )
      }
    e.Variable(var) ->
      case map.get(env, var) {
        Ok(value) -> cont(value)
        Error(Nil) -> Error(string.concat(["missing value: ", var]))
      }
    e.Function(pattern, body) -> cont(r.Function(pattern, body, env, None))
    e.Call(func, arg) ->
      do_eval(
        func,
        env,
        fn(func) {
          do_eval(
            arg,
            env,
            fn(arg) {
              try value = eval_call(func, arg)
              case value {
                // when an Effect occurs evaluation needs to stop until the effect finds a handler.
                // continuing evaluation can create multiple effects that would need a second tree walk to be continued
                r.Effect(name, value, next) ->
                  Ok(r.Effect(
                    name,
                    value,
                    fn(x) {
                      // Is there a nicer way to call this is we have defuntionalized
                      try x = cont(x)
                      next(x)
                    },
                  ))
                _ -> cont(value)
              }
            },
          )
        },
      )

    e.Hole -> Error("interpreted a program with a hole")
    e.Provider(_, _, generated) -> {
      io.debug(generated)
      // TODO this could be typed better with an anonymous fn that first unwraps then goes to nil
      do_eval(dynamic.unsafe_coerce(generated), env, cont)
    }
  }
  // todo("providers should have been expanded before evaluation")
}

pub fn eval_call(func, arg) {
  case func {
    r.Function(pattern, body, captured, self) -> {
      let captured = case self {
        Some(label) -> map.insert(captured, label, func)
        None -> captured
      }
      assert Ok(inner) = r.extend_env(captured, pattern, arg)
      eval(body, inner)
    }
    r.BuiltinFn(func) -> func(arg)
    r.Coroutine(forked) -> Ok(r.Ready(forked, arg))
    _ -> {
      io.debug(func)
      todo("Should never be called")
    }
  }
}
