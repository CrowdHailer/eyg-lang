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
    loop(cont)
}

fn loop(cont) { 
    case cont {
        Done(value) -> value
        Cont(value, cont) -> {
            loop(cont(value))
        }
    }
}

// pub type Cont = Option(fn(r.Object) -> Cont)
pub type Cont {
    Done(r.Object)
    Cont(r.Object, fn(r.Object) -> Cont)
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
                    Ok(value) -> cont(value)
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
            cont(value)
        }
        e.Function(pattern, body) -> {
            cont(r.Function(pattern, body, env, None))
        }
        e.Call(func, arg) -> {
            step(func, env, fn(func) {
                step(arg, env, fn(arg) {
                    cont(r.exec_call(func, arg))
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

