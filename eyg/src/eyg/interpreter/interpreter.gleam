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
}

fn value_map(pairs, func) { 
    list.map(pairs, fn(pair) { 

    let #(k, v) = pair
        #(k, func(v))
     })
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


pub fn run(source, env, coroutines)  {
    case exec_old(source, env) {
        Ready(coroutine, next) -> {
            let pid = list.length(coroutines)
            let coroutines = list.append(coroutines, [coroutine])
            run_call(next, Pid(pid), coroutines) 
        }
        done -> #(done, coroutines)
    }
}

// There's probably a nice way to have run call be the only func that necessary if I assume a main fn
pub fn run_call(next, arg, coroutines)  {
    case exec_call(next, arg) {
        Ready(coroutine, next) -> {
            let pid = list.length(coroutines)
            let coroutines = list.append(coroutines, [coroutine])
            run_call(next, Pid(pid), coroutines)
        }
        done -> #(done, coroutines)
    }
}

pub fn exec_old(source, env)  {
    let #(_, s) = source
    case s {
        e.Binary(value) -> Binary(value)
        e.Tuple(elements) -> Tuple(list.map(elements, exec_old(_, env)))
        e.Record(fields) -> Record(value_map(fields, exec_old(_, env)))
        e.Access(record, key) -> {
            assert Record(fields) = exec_old(record, env)
            case list.key_find(fields, key) {
                Ok(value) -> value
                _ -> {
                    io.debug(key)
                    todo("missing key in record")
                }
            }
        }
        e.Tagged(tag, value) -> Tagged(tag, exec_old(value, env))
        e.Case(value, branches) -> {
            assert Tagged(tag, value) = exec_old(value, env)
            assert Ok(#(_, pattern, then)) = list.find(branches, fn(branch) {
                let #(t, _, _) = branch
                t == tag
            })
            let env = extend_env(env, pattern, value)
            exec_old(then, env)

        }
        e.Let(pattern, value, then) -> {
            case pattern, value {
                p.Variable(label), #(_, e.Function(pattern, body)) -> {
                    map.insert(env, label, Function(pattern, body, env, Some(label)))
                }
                _,_ -> extend_env(env, pattern, exec_old(value, env))
            }
            |> exec_old(then, _)
        }
        e.Variable(var) -> {
            assert Ok(value) = map.get(env, var)
            value
        }
        e.Function(pattern, body) -> {
            Function(pattern, body, env, None)
        }
        e.Call(func, arg) -> {
            let func = exec_old(func, env)
            let arg = exec_old(arg, env)            
            exec_call(func, arg)

        }
        e.Hole() -> todo("interpreted a program with a hole")
        e.Provider(_, _, generated) -> {
            // TODO this could be typed better with an anonymous fn that first unwraps then goes to nil
            exec_old(dynamic.unsafe_coerce(generated), env)
            // todo("providers should have been expanded before evaluation")
            }
    }
}

pub fn exec_call(func, arg) {
    case func {
            Function(pattern, body, captured, self)  -> {
            let captured = case self {
                Some(label) -> map.insert(captured, label, func)
                None -> captured
            }
            let inner = extend_env(captured, pattern, arg)
            exec_old(body, inner)
        }
        BuiltinFn(func) -> {
            func(arg)
        }
        Coroutine(forked) -> {
            Ready(forked, arg)
        }
        _ -> todo("Should never be called")
    }
}

pub fn spawn(x)  {
        assert Function(pattern, body, env, self) = x
        // todo("inside spawn")
        Coroutine(x)
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
        }
}

fn exec_tuple(elements, env, acc, k) { 
    case elements {
        [] -> k(Tuple(list.reverse(acc))) 
        [e, ..elements] -> exec2(e, env, fn(value) {
            exec_tuple(elements, env, [value, ..acc], k)
        })
    }
 }

 fn exec_record(fields, env, acc, k) { 
    case fields {
        [] -> k(Record(list.reverse(acc))) 
        [f, ..fields] -> {
             let #(name, e) = f
            exec2(e, env, fn(value) {
               
                exec_record(fields, env, [#(name, value), ..acc], k)
            })
        }
    }
 }


// ----------------------------
// pub fn exec(source, env) {
//     exec2(source, env, fn(x){x})
// }

pub fn exec2(source, env, kont)  {
    let #(_, s) = source
    case s {
        e.Binary(content) -> kont(Binary(content))
        e.Tuple(elements) -> {
            exec_tuple(elements, env, [], kont)
        }
        e.Record(fields) -> exec_record(fields, env, [], kont)
        e.Access(record, key) -> {
            exec2(record, env, fn(value) {
                assert Record(fields) = value
                case list.key_find(fields, key) {
                    Ok(value) -> kont(value)
                    _ -> {
                        io.debug(key)
                        todo("missing key in record")
                    }
                }
            })
        }
        e.Tagged(tag, value) -> {
            exec2(value, env, fn(value) {
                kont(Tagged(tag, value))
            })
        }
        e.Case(value, branches) -> {
           exec2(value, env, fn(value) {
                assert Tagged(tag, value) = value
                assert Ok(#(_, pattern, then)) = list.find(branches, fn(branch) {
                    let #(t, _, _) = branch
                    t == tag
                })
                let env = extend_env(env, pattern, value)
                exec2(then, env, kont)
           })
        }
        e.Let(pattern, value, then) -> {
            case pattern, value {
                p.Variable(label), #(_, e.Function(pattern, body)) -> {
                   exec2(then, map.insert(env, label, Function(pattern, body, env, Some(label))), kont)
                }
                _,_ -> exec2(value, env, fn(value) {
                    extend_env(env, pattern, value)
                    |> exec2(then, _, kont)
                }) 
            }
        }
        e.Variable(var) -> {
            assert Ok(value) = map.get(env, var)
            kont(value)
        }
        e.Function(pattern, body) -> {
            kont(Function(pattern, body, env, None))
        }
        e.Call(func, arg) -> {
            exec2(func, env, fn(func) {
                exec2(arg, env, fn(arg) {
                    io.debug(exec_call(func, arg))
                    kont(exec_call(func, arg))
                })            
            })

        }
        e.Hole() -> todo("interpreted a program with a hole")
        e.Provider(_, _, generated) -> {
            // TODO this could be typed better with an anonymous fn that first unwraps then goes to nil
            exec2(dynamic.unsafe_coerce(generated), env, kont)
            // todo("providers should have been expanded before evaluation")
            }
    }
}

pub type Step(a,b) {
    More(v: e.Expression(a,b), e: map.Map(String, Object), k: Option(fn(Object) -> Step(a,b)), )
    Done(v: Object)
}

fn apply(next, value) { 
    case next {
        Some(k) -> Done(value )
        None ->Done(value)
    }
    // #(next, value)
}

pub fn exec(source, env) {
    do_exec(source, env, None)
    // v
}

fn do_exec(source, env, kont) { 
    case exec3(source, env, kont) {
        Done(value) -> value
        More(exp,env,cont) ->  {
            io.debug(exp)
            do_exec(source, env, kont)
        }
    }
 }

// fn do_exec(source, env) { 
    
// }

fn exec_tuple3(elements: List(e.Expression(_,_)), env, acc, k)  { 
    case elements {
        [] -> apply(k,Tuple(list.reverse(acc))) 
        [e, ..elements] -> More(e, env, Some(fn(value) {
            exec_tuple3(elements, env, [value, ..acc], k)
        }))
    }
 }

 fn exec_record3(fields, env, acc, k) { 
    case fields {
        [] -> apply(k,Record(list.reverse(acc))) 
        [f, ..fields] -> {
             let #(name, e) = f
            More(e, env, Some(fn(value) {
               
                exec_record3(fields, env, [#(name, value), ..acc], k)
            }))
        }
    }
 }
pub fn cap(f) {
    fn(value) {
        #(value, Some(fn(){f(value)}))
    }
}

import gleam/iterator
// it's not a proper linked list the stack is a new recursive type
pub fn exec3(source, env, kont)  {
    let #(_, s) = source
    case s {
        e.Binary(content) -> apply(kont,Binary(content))
        e.Tuple(elements) -> {
            exec_tuple3(elements, env, [], kont)
        }
        e.Record(fields) -> exec_record3(fields, env, [], kont)
        e.Access(record, key) -> {
            More(record, env, Some(fn(value) {
                assert Record(fields) = value
                case list.key_find(fields, key) {
                    Ok(value) -> apply(kont, value)
                    _ -> {
                        io.debug(key)
                        todo("missing key in record")
                    }
                }
            }))
        }
        e.Tagged(tag, value) -> {
            More(value, env, Some(fn(value) {
                apply(kont, Tagged(tag, value))
            }))
        }
        e.Case(value, branches) -> {
           More(value, env, Some(fn(value) {
                assert Tagged(tag, value) = value
                assert Ok(#(_, pattern, then)) = list.find(branches, fn(branch) {
                    let #(t, _, _) = branch
                    t == tag
                })
                let env = extend_env(env, pattern, value)
                More(then, env, Some(apply(kont,_)))
           }))
        }
        e.Let(pattern, value, then) -> {
            case pattern, value {
                p.Variable(label), #(_, e.Function(pattern, body)) -> {
                   More(then, map.insert(env, label, Function(pattern, body, env, Some(label))), Some(apply(kont,_)))
                }
                _,_ -> More(value, env, Some(fn(value) {
                    extend_env(env, pattern, value)
                    |> More(then, _, Some(apply(kont,_)))
                }) )
            }
        }
        e.Variable(var) -> {
            assert Ok(value) = map.get(env, var)
            apply(kont, value)
        }
        e.Function(pattern, body) -> {
            apply(kont, Function(pattern, body, env, None))
        }
        e.Call(func, arg) -> {
            More(func, env, Some(fn(func) {
                More(arg, env, Some(fn(arg) {
                    io.debug(exec_call(func, arg))
                    apply(kont, exec_call(func, arg))
                })           ) 
            }))

        }
        e.Hole() -> todo("interpreted a program with a hole")
        e.Provider(_, _, generated) -> {
            // TODO this could be typed better with an anonymous fn that first unwraps then goes to nil
            More(dynamic.unsafe_coerce(generated), env, Some(apply(kont,_)))
            // todo("providers should have been expanded before evaluation")
            }
    }
}