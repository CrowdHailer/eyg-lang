import gleam/map
import eyg/interpreter/interpreter.{Object} as r
import eyg/ast/expression as e
import eyg/ast/pattern as p

pub fn eval(source, env, kont) {
  let #(_, s) = source
  case s {
    e.Binary(bin) -> kont(r.Binary(bin))
    e.Tagged(tag, value) -> eval(value, env, fn(value) { r.Tagged(tag, value) })
    e.Let(p.Variable(var), value, then) ->
      eval(
        value,
        env,
        fn(value) {
          let env = map.insert(env, var, value)
          eval(then, env, kont)
        },
      )
    _ -> todo
  }
}

pub fn iter(source, env, kont) {
  let #(_, s) = source
  case s {
    e.Binary(bin) -> #(r.Binary(bin), env, kont)
    e.Tagged(tag, value) -> #(
      value,
      env,
      fn(value, env, kont) { r.Tagged(tag, value) },
    )
    e.Let(p.Variable(var), value, then) ->
      iter(
        value,
        env,
        fn(value, env, kont) {
          let env = map.insert(env, var, value)
          iter(then, env, value)
        },
      )
  }
}

pub fn loop(value, env, kont) -> Nil {
  // iter is start conditions
  //   let #(value, env, kont) = iter(source, env, [])
  case kont {
    [] -> value
    [k, kont] -> {
      let #(value, env, kont) = k(value, env)
      loop(value, env, kont)
    }
  }
}
