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

fn eval_tuple(elements, env, acc, cont) { 
    case elements {
        [] -> cont(r.Tuple(list.reverse(acc))) 
        [e, ..elements] -> do_eval(e, env, fn(value) {
            eval_tuple(elements, env, [value, ..acc], cont)
        })
    }
 }

 fn exec_record(fields, env, acc, cont) { 
    case fields {
        [] -> cont(r.Record(list.reverse(acc))) 
        [f, ..fields] -> {
             let #(name, e) = f
            do_eval(e, env, fn(value) {
               
                exec_record(fields, env, [#(name, value), ..acc], cont)
            })
        }
    }
 }


pub fn eval(source, env) {
    do_eval(source, env, fn(x){x})
}

pub fn do_eval(source, env, cont)  {
    let #(_, s) = source
    case s {
        e.Binary(content) -> cont(r.Binary(content))
        e.Tuple(elements) -> {
            eval_tuple(elements, env, [], cont)
        }
        e.Record(fields) -> exec_record(fields, env, [], cont)
        e.Access(record, key) -> {
            do_eval(record, env, fn(value) {
                assert r.Record(fields) = value
                case list.key_find(fields, key) {
                    Ok(value) -> cont(value)
                    _ -> {
                        io.debug(key)
                        todo("missing key in record")
                    }
                }
            })
        }
        e.Tagged(tag, value) -> {
            do_eval(value, env, fn(value) {
                cont(r.Tagged(tag, value))
            })
        }
        e.Case(value, branches) -> {
           do_eval(value, env, fn(value) {
                assert r.Tagged(tag, value) = value
                assert Ok(#(_, pattern, then)) = list.find(branches, fn(branch) {
                    let #(t, _, _) = branch
                    t == tag
                })
                let env = r.extend_env(env, pattern, value)
                do_eval(then, env, cont)
           })
        }
        e.Let(pattern, value, then) -> {
            case pattern, value {
                p.Variable(label), #(_, e.Function(pattern, body)) -> {
                   do_eval(then, map.insert(env, label, r.Function(pattern, body, env, Some(label))), cont)
                }
                _,_ -> do_eval(value, env, fn(value) {
                    r.extend_env(env, pattern, value)
                    |> do_eval(then, _, cont)
                }) 
            }
        }
        e.Variable(var) -> {
            assert Ok(value) = map.get(env, var)
            cont(value)
        }
        e.Function(pattern, body) -> {
            cont(r.Function(pattern, body, env, None))
        }
        e.Call(func, arg) -> {
            do_eval(func, env, fn(func) {
                do_eval(arg, env, fn(arg) {
                    cont(exec_call(func, arg))
                })            
            })

        }
        e.Hole() -> todo("interpreted a program with a hole")
        e.Provider(_, _, generated) -> {
            // TODO this could be typed better with an anonymous fn that first unwraps then goes to nil
            do_eval(dynamic.unsafe_coerce(generated), env, cont)
            // todo("providers should have been expanded before evaluation")
            }
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