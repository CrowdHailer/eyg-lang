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
import eyg/interpreter/interpreter as r

pub fn eval(source, env) {
    let cont = step(source, env, fn(value) { Done(value) })
    loop(cont, [])
}

fn loop(cont, processes) { 
    case cont {
        Done(value) -> value
        Cont(value, cont) -> {
            loop(cont(value), processes)
        }
        // Spawn(func) -> {
        //     let pid = list.length(processes)
        //     let processes = [func, ..processes]
        //     loop(r.Function(p.Variable("then"), e.call(e.variable("then"), )), processes)
        // }
    }
}

// pub type Cont = Option(fn(r.Object) -> Cont)
pub type Cont {
    Done(r.Object)
    Cont(r.Object, fn(r.Object) -> Cont)
    // Spawn(r.Object)
}

fn eval_tuple(elements, env, acc, cont) { 
    case elements {
        [] -> Cont(r.Tuple(list.reverse(acc)), cont) 
        [e, ..elements] -> step(e, env, fn(value) {
            eval_tuple(elements, env, [value, ..acc], cont)
        })
    }
 }

 fn eval_record(fields, env, acc, cont) { 
    case fields {
        [] -> Cont(r.Record(list.reverse(acc)), cont) 
        [f, ..fields] -> {
             let #(name, e) = f
            step(e, env, fn(value) {
                eval_record(fields, env, [#(name, value), ..acc], cont)
            })
        }
    }
 }

pub fn step(source, env, cont)  {
    let #(_, s) = source
    case s {
        e.Binary(content) -> Cont(r.Binary(content), cont)
        e.Tuple(elements) -> {
            eval_tuple(elements, env, [], cont)
        }
        e.Record(fields) -> eval_record(fields, env, [], cont)
        e.Access(record, key) -> {
            step(record, env, fn(value) {
                assert r.Record(fields) = value
                case list.key_find(fields, key) {
                    Ok(value) -> Cont(value, cont)
                    _ -> {
                        io.debug(key)
                        todo("missing key in record")
                    }
                }
            })
        }
        e.Tagged(tag, value) -> {
            step(value, env, fn(value) {
                Cont(r.Tagged(tag, value), cont)
            })
        }
        e.Case(value, branches) -> {
           step(value, env, fn(value) {
                assert r.Tagged(tag, value) = value
                assert Ok(#(_, pattern, then)) = list.find(branches, fn(branch) {
                    let #(t, _, _) = branch
                    t == tag
                })
                let env = r.extend_env(env, pattern, value)
                step(then, env, cont)
           })
        }
        e.Let(pattern, value, then) -> {
            case pattern, value {
                p.Variable(label), #(_, e.Function(pattern, body)) -> {
                   step(then, map.insert(env, label, r.Function(pattern, body, env, Some(label))), cont)
                }
                _,_ -> step(value, env, fn(value) {
                    r.extend_env(env, pattern, value)
                    |> step(then, _, cont)
                }) 
            }
        }
        e.Variable(var) -> {
            assert Ok(value) = map.get(env, var)
            Cont(value, cont)
        }
        e.Function(pattern, body) -> {
            Cont(r.Function(pattern, body, env, None), cont)
        }
        e.Call(func, arg) -> {
            step(func, env, fn(func) {
                step(arg, env, fn(arg) {
                    exec_call(func, arg, cont)
                })            
            })

        }
        e.Hole() -> todo("interpreted a program with a hole")
        e.Provider(_, _, generated) -> {
            // TODO this could be typed better with an anonymous fn that first unwraps then goes to nil
            step(dynamic.unsafe_coerce(generated), env, cont)
            // todo("providers should have been expanded before evaluation")
            }
    }
}

pub fn exec_call(func, arg, cont) {
    let s = spawn
    case func {
            r.Function(pattern, body, captured, self)  -> {
            let captured = case self {
                Some(label) -> map.insert(captured, label, func)
                None -> captured
            }
            let inner = r.extend_env(captured, pattern, arg)
            step(body, inner, cont)
        }
        // r.BuiltinFn(func) if func == s -> {
        //     // io.debug(cont)
        //     // todo("spwan")
        //     Spawn(func)
        //     // io.debug(func == spawn)
        //     // Cont(func(arg), cont)
        // }
        r.Coroutine(forked) -> {
            Cont(r.Ready(forked, arg), cont)
        }
        _ -> todo("Should never be called")
    }
}

pub fn spawn(x)  {
        // assert Function(pattern, body, env, self) = x
        // todo("inside spawn")
        r.Coroutine(x)
}