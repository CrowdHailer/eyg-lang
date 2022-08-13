import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/option.{Option, Some, None}
import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/codegen/javascript

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
    Native(Dynamic)
}


pub fn extend_env(env, pattern, object) { 
    case pattern {
        p.Variable(var) ->  map.insert(env, var, object)
        p.Tuple(keys) -> {
            assert Tuple(elements) = object
            assert Ok(pairs) = list.strict_zip(keys, elements)
            list.fold(pairs, env, fn(env, pair) { 
                let #(var, value)= pair
                map.insert(env, var, value)
            })
            }
        p.Record(fields) -> todo("not supporting record fields here yet")
    }
 }



pub fn render_var(assignment) { 
    let #(var, object) = assignment
    case var {
        "" -> "" 
        _ -> string.concat(["let ", var, " = ", render_object(object), ";"])
    }
 }

fn render_object(object) {
case object {
            Binary(content) -> string.concat([ "\"", javascript.escape_string(content), "\""])
            Pid(pid) -> int.to_string(pid)
            Tuple(_) -> "null"
            Record(fields) -> {
                let term = list.map(
                    fields,
                    fn(field) {
                    let #(name, object) = field
                    string.concat([name, ": ", render_object(object)])
                    },
                )
                |> string.join(", ")
                string.concat(["{", term, "}"])
            }
            Tagged(_, _) ->"null"
            // Builtins should never be included, I need to check variables used in a previous step
            // Function(_,_,_,_) -> todo("this needs compile again but I need a way to do this without another type check")
            Function(_,_,_,_) -> "null"
            BuiltinFn(_) -> "null"
            Coroutine(_) -> "null"
            Ready(_, _) -> "null"
            Native(_) -> "null"
        }
}
