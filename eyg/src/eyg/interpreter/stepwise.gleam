import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/option.{Option, Some, None}
import gleam/int
import gleam/list
import gleam/map
import gleam/string
import gleam/function
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/codegen/javascript
import eyg/interpreter/interpreter as r
import gleam/javascript as real_js
import gleam/javascript/promise.{Promise}

fn write_html(o) { 
    assert r.Binary(content) = o
    write_into_div(content)
    r.BuiltinFn(write_html)
}
fn set_key_handler(o) { 
   todo("we don't use this but might with key handler as mutable ref")
}

external fn write_into_div(String) -> Nil =
  "../../browser_ffi.js" "writeIntoDiv"
external fn try_catch(fn() -> b) -> Result(b, string) =
  "../../browser_ffi.js" "tryCatch"
external fn do_fetch(String) -> Promise(String) =
  "../../browser_ffi.js" "fetchText"

pub fn run_browser(source)  {
    let r = try_catch(fn() { 
        start(source, map.new())
    })    
}

pub fn fetch(o, ref)  {
    assert r.Tuple([r.Binary(url), callback]) = o
    promise.map(do_fetch(url), fn(body) {
        let processes = real_js.dereference(ref)
        let cont = step_call(callback, r.Binary(body), fn(value) { Done(value) })
        let #(processes, messages, value) = loop(cont, processes, [])
        let messages = list.reverse(messages)
        let #(processes, key_handler) = deliver_messages(processes, messages, r.Binary("we ignore this key handler"))
        // Key handler is thrown away here needs to be in mutable state ref TODO
        real_js.set_reference(ref, processes)
    })
    // could be promise to value 
    r.BuiltinFn(fetch(_, ref))
}

pub fn start(source, env) { 
    let ref = real_js.make_reference([])
    let processes = [r.BuiltinFn(write_html), r.BuiltinFn(set_key_handler), r.BuiltinFn(fetch(_, ref))]

    // easier than making a step call function does need to ensure there is no system key in env
    let program = e.call(source, e.variable("system"))
    let env = env
    |> map.insert( "system", r.Record([#("ui", r.Pid(0)), #("on_keypress", r.Pid(1)), #("fetch", r.Pid(2))]))
    |> map.insert("spawn", r.BuiltinFn(spawn))
    |> map.insert("send", r.BuiltinFn(send))
    |> map.insert("harness", r.Record([#("debug", r.BuiltinFn(io.debug))]))
    let cont = step(program, env, fn(value) { Done(value) })
    let #(processes, messages, _value) = loop(cont, processes, [])
    let messages = list.reverse(messages)
    let handler = r.Function(p.Variable("key"), e.call(e.variable("send"), e.tuple_([e.access(e.variable("system"), "ui"), e.variable("key")])), env, None)
    let #(processes, key_handler) = deliver_messages(processes, messages, handler)
    real_js.set_reference(ref, processes)
    #(ref, key_handler)
}

pub fn handle_keydown(state, key) {
    let #(ref, key_handler) = state
    let processes = real_js.dereference(ref)
    let cont = step_call(key_handler, r.Binary(key), fn(value) { Done(value) })
    let #(processes, messages, _value) = loop(cont, processes, [])
    let messages = list.reverse(messages)
    // send -> dispatch ~~~> deliver -> receive
    // TODO this should be r.function
    let #(processes, key_handler) = deliver_messages(processes, messages, key_handler)
    real_js.set_reference(ref, processes)
    #(ref, key_handler)
}

// needs map_at
fn deliver_messages(processes, messages, key_handler) { 
    case messages {
        [] -> #(processes, key_handler) 
        [r.Tuple([r.Pid(1), new_handler]), ..rest] -> {
            deliver_messages(processes, rest, new_handler)
        }
        [r.Tuple([r.Pid(i), message]), ..rest] -> {
            let pre = list.take(processes, i)
            let [process, ..post] = list.drop(processes, i)
            // need messages offset
            let cont = step_call(process, message, fn(value) { Done(value) })
            // TODO need function to hadnle messages here
            let #([],[], value) = loop(cont, [], [])
            let processes = list.flatten([pre, [value], post])
            deliver_messages(processes, rest, key_handler)
        }
    }
}

pub fn eval(source, env) {
    let #(_, _, value) = effect_eval(source, env)
    value
}

pub fn effect_eval(source, env) {
    let cont = step(source, env, fn(value) { Done(value) })
    loop(cont, [], [])
}

pub fn loop(cont, processes, messages) { 
    case cont {
        Done(value) -> #(processes, messages, value)
        Cont(value, cont) -> {
            // let #(_, value) = value
            loop(cont(value), processes, messages)
        }
        Eff(effect, cont) -> {
            // handle effect
            case effect {
                Spawn(func) -> {
                    let pid = list.length(processes)
                    // TODO need to add process at the end
                    let processes = list.append(processes, [func])
                    let value = r.Function(p.Variable("then"), e.call(e.variable("then"), e.variable("pid")), map.new() |> map.insert("pid", r.Pid(pid)), None)

                    loop(cont(value), processes, messages)
                }
                Send(message) -> {
                    let messages = [message, ..messages]
                    let value = r.Function(p.Variable("then"), e.call(e.variable("then"), e.tuple_([])), map.new() , None)
                    loop(cont(value), processes, messages)
                }
            }
        }
    }
}

// pub type Cont = Option(fn(r.Object) -> Cont)
pub type Cont {
    Done(r.Object)
    Cont( r.Object, fn(r.Object) -> Cont)
    Eff(Effect, fn(r.Object) -> Cont)
}

pub type Effect {
    Spawn(func: r.Object)
    Send(pid_and_message: r.Object)
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
                assert Ok(env) = r.extend_env(env, pattern, value)
                step(then, env, cont)
           })
        }
        e.Let(pattern, value, then) -> {
            case pattern, value {
                p.Variable(label), #(_, e.Function(pattern, body)) -> {
                   step(then, map.insert(env, label, r.Function(pattern, body, env, Some(label))), cont)
                }
                _,_ -> step(value, env, fn(value) {
                    assert Ok(env) = r.extend_env(env, pattern, value)
                    step(then, env, cont)
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
                    step_call(func, arg, cont)
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

pub fn step_call(func, arg, cont) {
    let sp = spawn
    let se = send
    case func {
            r.Function(pattern, body, captured, self)  -> {
            let captured = case self {
                Some(label) -> map.insert(captured, label, func)
                None -> captured
            }
            assert Ok(inner) = r.extend_env(captured, pattern, arg)
            step(body, inner, cont)
        }
        r.BuiltinFn(func) if func == sp -> {
            // io.debug(cont)
            // todo("spwan")
            // Spawn(func)
            // io.debug(func == spawn)
            // Theres no state too pass in here TODO
            // Cont(r.Spawn(fn), )
            // Cont(#([Spawn(func)], todo), cont)
            io.debug("spawn arg ============")
            io.debug(arg)
            Eff(Spawn(arg), cont)
        }
        r.BuiltinFn(func) if func == se -> {
            Eff(Send(arg), cont)
        }
        r.BuiltinFn(func) -> {
            Cont(func(arg), cont)
        }
        // r.Coroutine(forked) -> {
        //     Cont(r.Ready(forked, arg), cont)
        // }
        _ -> {
            io.debug(func)
            todo("Should never be called")
        }
    }
}

pub fn spawn(x)  {
        // assert Function(pattern, body, env, self) = x
        // todo("inside spawn")
        // r.Coroutine(x)
        todo("this is the spawn function")
        // r.Binary("this is the spawn fn which is evaled at the beginning because of the compile step which we should stop TODO")
        // r.Function(p.Variable("x"), e.variable("x"), map.new(), None)
}


pub fn send(x)  {
        // assert Function(pattern, body, env, self) = x
        // todo("inside spawn")
        // r.Coroutine(x)
        todo("this is the send function")
}