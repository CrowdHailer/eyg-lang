import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/list
import gleam/map
import eyg/ast/expression as e
import eyg/ast/pattern as p

pub type Object {
    Binary(String)
    Tuple(List(Object))
    Record(List(#(String, Object)))
    Tagged(String, Object)
    Function(p.Pattern, e.Expression(Dynamic, Dynamic), map.Map(String, Object))
}

fn value_map(pairs, func) { 
    list.map(pairs, fn(pair) { 

    let #(k, v) = pair
        #(k, func(v))
     })
 }

fn extend_env(env, pattern, object) { 
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

pub fn exec(source, env)  {
    let #(_, source) = source
    case source {
        e.Binary(value) -> Binary(value)
        e.Tuple(elements) -> Tuple(list.map(elements, exec(_, env)))
        e.Record(fields) -> Record(value_map(fields, exec(_, env)))
        e.Access(record, key) -> {
            assert Record(fields) = exec(record, env)
            assert Ok(value) = list.key_find(fields, key)
            value
        }
        e.Tagged(tag, value) -> Tagged(tag, exec(value, env))
        e.Case(value, branches) -> {
            assert Tagged(tag, value) = exec(value, env)
            assert Ok(#(_, pattern, then)) = list.find(branches, fn(branch) {
                let #(t, _, _) = branch
                t == tag
            })
            let env = extend_env(env, pattern, value)
            exec(then, env)

        }
        e.Let(pattern, value, then) -> {
            exec(then, extend_env(env, pattern, exec(value, env)))
        }
        e.Variable(var) -> {
            assert Ok(value) = map.get(env, var)
            value
        }
        e.Function(pattern, body) -> {
            Function(pattern, body, env)
        }
        e.Call(func, arg) -> {
            assert Function(pattern, body, captured) = exec(func, env)
            let inner = extend_env(captured, pattern, exec(arg, env))
            exec(body, inner)

        }
        e.Hole() -> todo("interpreted a program with a hole")
        e.Provider(_, _, _) -> todo("providers should have been expanded before evaluation")
    }
}