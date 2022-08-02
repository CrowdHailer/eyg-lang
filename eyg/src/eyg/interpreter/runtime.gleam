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

fn apply(stack, value) { 
    // How do I thread env
    let #(value, env) = value
    case stack {
        [] -> value 
        [k, ..stack] -> apply(stack, k(value))
    }
 }

// Tuple apply takes next n items off stack but thows continuation
pub fn compile(source, env)  {
    do_compile(source, env, [])
}
fn do_compile(source, env, stack)  {
    let #(_, s) = source
    case s {
        e.Binary(content) -> #(Binary(content), env, stack)
        // fn(_env) { bin }
        // e.Tuple([e1,e2,e3]) -> {
        //     eval(e1, env, fn(e1) {
        //         eval(e2, env, fn(e3) {
        //             eval(e3, env, fn(e3) { Tuple([e1,e2,e3])})
        //         })
        //     })

        //     // I think that this would be represended as a v with an array value that we then wrap in a tuple
        //     // This is interesting but we need to do the corountines stuff first
        // }
        e.Tagged(k, value) -> {
            let kont = fn(value, env) { #(Tagged(k, value), env) }
            let stack = [kont, ..stack]
            do_compile(value, env, stack)
        }
        // e.Let(p.Variable(var), value, then) -> {
        //     // fn(value, env) { #(value, map.insert(env, var,value)) }
        //     let stack = do_compile(value, env, [])
        //     let k = fn(v, env) {

        //     }
        // }
        // e.Let(p.Variable(var), value, then) -> {
        //     // value can probably be none here
        //     let kont = fn(value) { #(value, map.insert(env, var,value)) }
        //     let then_kont = fn(value) {
        //         value
        //     }
        //     let stack = [kont, then_kont, ..stack]
            
        // }
        _ -> todo("incompile")
    }
}