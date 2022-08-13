import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/option.{Option, Some, None}
import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/interpreter/interpreter as r

pub fn eval(source, env)  {
    let #(_, s) = source
    case s {
        e.Binary(value) -> r.Binary(value)
        e.Tuple(elements) -> r.Tuple(list.map(elements, eval(_, env)))
        e.Record(fields) -> r.Record(value_map(fields, eval(_, env)))
        e.Access(record, key) -> {
            assert r.Record(fields) = eval(record, env)
            case list.key_find(fields, key) {
                Ok(value) -> value
                _ -> {
                    io.debug(key)
                    todo("missing key in record")
                }
            }
        }
        e.Tagged(tag, value) -> r.Tagged(tag, eval(value, env))
        e.Case(value, branches) -> {
            assert r.Tagged(tag, value) = eval(value, env)
            assert Ok(#(_, pattern, then)) = list.find(branches, fn(branch) {
                let #(t, _, _) = branch
                t == tag
            })
            let env = r.extend_env(env, pattern, value)
            eval(then, env)

        }
        e.Let(pattern, value, then) -> {
            case pattern, value {
                p.Variable(label), #(_, e.Function(pattern, body)) -> {
                    map.insert(env, label, r.Function(pattern, body, env, Some(label)))
                }
                _,_ -> r.extend_env(env, pattern, eval(value, env))
            }
            |> eval(then, _)
        }
        e.Variable(var) -> {
            assert Ok(value) = map.get(env, var)
            value
        }
        e.Function(pattern, body) -> {
            r.Function(pattern, body, env, None)
        }
        e.Call(func, arg) -> {
            let func = eval(func, env)
            let arg = eval(arg, env)            
            exec_call(func, arg)

        }
        e.Hole() -> todo("interpreted a program with a hole")
        e.Provider(_, _, generated) -> {
            // TODO this could be typed better with an anonymous fn that first unwraps then goes to nil
            eval(dynamic.unsafe_coerce(generated), env)
            // todo("providers should have been expanded before evaluation")
            }
    }
}


pub fn run(source, env, coroutines)  {
    case eval(source, env) {
        r.Ready(coroutine, next) -> {
            let pid = list.length(coroutines)
            let coroutines = list.append(coroutines, [coroutine])
            run_call(next, r.Pid(pid), coroutines) 
        }
        done -> #(done, coroutines)
    }
}

// There's probably a nice way to have run call be the only func that necessary if I assume a main fn
pub fn run_call(next, arg, coroutines)  {
    case exec_call(next, arg) {
        r.Ready(coroutine, next) -> {
            let pid = list.length(coroutines)
            let coroutines = list.append(coroutines, [coroutine])
            run_call(next, r.Pid(pid), coroutines)
        }
        done -> #(done, coroutines)
    }
}


pub fn exec_call(func, arg) {
    case func {
            r.Function(pattern, body, captured, self)  -> {
            let captured = case self {
                Some(label) -> map.insert(captured, label, func)
                None -> captured
            }
            let inner = r.extend_env(captured, pattern, arg)
            eval(body, inner)
        }
        r.BuiltinFn(func) -> {
            func(arg)
        }
        r.Coroutine(forked) -> {
            r.Ready(forked, arg)
        }
        _ -> todo("Should never be called")
    }
}

pub fn spawn(x)  {
    assert r.Function(pattern, body, env, self) = x
    r.Coroutine(x)
}

fn value_map(pairs, func) { 
    list.map(pairs, fn(pair) { 

    let #(k, v) = pair
        #(k, func(v))
     })
 }
