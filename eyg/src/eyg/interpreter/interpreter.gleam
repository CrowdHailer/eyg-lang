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
import eyg/analysis
import eyg/typer
import eyg/typer/monotype as t

pub type Object {
  Binary(String)
  Tuple(List(Object))
  Record(List(#(String, Object)))
  Tagged(String, Object)
  Function(
    p.Pattern,
    e.Expression(Dynamic, Dynamic),
    map.Map(String, Object),
    Option(String),
  )
  BuiltinFn(fn(Object) -> Result(Object, String))
  Native(Dynamic)
  Effect(String, Object, fn(Object) -> Result(Object, String))
}

pub fn extend_env(env, pattern, object) {
  case pattern {
    p.Variable(var) -> Ok(map.insert(env, var, object))
    p.Tuple(keys) ->
      case object {
        Tuple(elements) ->
          case list.strict_zip(keys, elements) {
            Ok(pairs) ->
              Ok(list.fold(
                pairs,
                env,
                fn(env, pair) {
                  let #(var, value) = pair
                  map.insert(env, var, value)
                },
              ))
            Error(reason) -> Error("needs better error")
          }
        _ -> Error("not a tuple")
      }

    p.Record(fields) -> {
      io.debug(fields)
      todo("not supporting record fields here yet")
    }
  }
}
