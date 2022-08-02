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
    case eval(source, env) {
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

pub fn eval(source, env)  {
    let #(_, s) = source
    case s {
        e.Binary(value) -> Binary(value)
        e.Tuple(elements) -> Tuple(list.map(elements, eval(_, env)))
        e.Record(fields) -> Record(value_map(fields, eval(_, env)))
        e.Access(record, key) -> {
            assert Record(fields) = eval(record, env)
            case list.key_find(fields, key) {
                Ok(value) -> value
                _ -> {
                    io.debug(key)
                    todo("missing key in record")
                }
            }
        }
        e.Tagged(tag, value) -> Tagged(tag, eval(value, env))
        e.Case(value, branches) -> {
            assert Tagged(tag, value) = eval(value, env)
            assert Ok(#(_, pattern, then)) = list.find(branches, fn(branch) {
                let #(t, _, _) = branch
                t == tag
            })
            let env = extend_env(env, pattern, value)
            eval(then, env)

        }
        e.Let(pattern, value, then) -> {
            case pattern, value {
                p.Variable(label), #(_, e.Function(pattern, body)) -> {
                    map.insert(env, label, Function(pattern, body, env, Some(label)))
                }
                _,_ -> extend_env(env, pattern, eval(value, env))
            }
            |> eval(then, _)
        }
        e.Variable(var) -> {
            assert Ok(value) = map.get(env, var)
            value
        }
        e.Function(pattern, body) -> {
            Function(pattern, body, env, None)
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

pub fn exec_call(func, arg) {
    case func {
            Function(pattern, body, captured, self)  -> {
            let captured = case self {
                Some(label) -> map.insert(captured, label, func)
                None -> captured
            }
            let inner = extend_env(captured, pattern, arg)
            eval(body, inner)
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
