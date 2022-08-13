import gleam/dynamic.{Dynamic}
import gleam/map
import gleam/option.{Option, Some, None}
import gleam/int
import gleam/list
import eyg/ast/expression as e
import eyg/ast/pattern as p

pub type Object {
    Binary(String)
    Pid(Int)
    Tuple(List(Object))
    Record(List(#(String, Object)))
    Tagged(String, Object)
    Function(p.Pattern, e.Expression(Dynamic, Dynamic), map.Map(String, Object), Option(String))
    Coroutine(Object)
    Ready(Object, Object)
    BuiltinFn(fn(Object) -> Object)
}