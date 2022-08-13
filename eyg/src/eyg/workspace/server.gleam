import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None}
import gleam/string
import eyg/interpreter/interpreter as r
import gleam/javascript as real_js
import eyg/interpreter/stepwise
import eyg/codegen/javascript

const true = r.Tagged("True", r.Tuple([]))
const false = r.Tagged("false", r.Tuple([]))

fn equal(object) { 
    assert r.Tuple([left, right]) = object
    case left == right {
        True -> true
        False -> false
    }
}

fn native(value) { 
    r.Native(dynamic.from(value))
}

fn std_int() { 
    r.Record([
        #("parse", r.BuiltinFn(fn(object){ 
            assert r.Binary(content) = object
            case int.parse(content) {
                Ok(value) -> r.Tagged("Ok", native(value)) 
                Error(reason) -> r.Tagged("Error", r.Record([]))
            }
         })),
        #("to_string", r.BuiltinFn(fn(object) { 
            assert r.Native(dynamic) = object
            assert Ok(value) = dynamic.int(dynamic)
            r.Binary(int.to_string(value))
        })),
        #("add", r.BuiltinFn(fn(object) { 
            assert r.Tuple([r.Native(d1), r.Native(d2)]) = object
            assert Ok(v1) = dynamic.int(d1)
            assert Ok(v2) = dynamic.int(d2)
            native(v1 + v2)
        })),
        #("multiply", r.BuiltinFn(fn(object) { 
            assert r.Tuple([r.Native(d1), r.Native(d2)]) = object
            assert Ok(v1) = dynamic.int(d1)
            assert Ok(v2) = dynamic.int(d2)
            native(v1 * v2)
        })),
        #("negate", r.BuiltinFn(fn(object) { 
            assert r.Native(dynamic) = object
            assert Ok(value) = dynamic.int(dynamic)
            native(-1 * value)
        })),
        #("zero", native(0)),
        #("one", native(1)),
        #("two", native(2)),
    ])    
}

fn std_string() { 
    r.Record([
        #("split", r.BuiltinFn(fn(object) {
            todo("string split")
        }))
    ])
}

fn concat(object) { 
    assert r.Tuple([r.Binary(left), r.Binary(right)]) = object
    r.Binary(string.concat([left, right]))
 }

fn prelude() { 
    map.new()
    |> map.insert("harness", r.Record([
        #("debug", r.BuiltinFn(io.debug)),
        #("concat", r.BuiltinFn(concat))
    ]))
    |> map.insert("equal", r.BuiltinFn(equal))
    |> map.insert("int", std_int())
    |> map.insert("string", std_string())
    |> map.insert("spawn", r.BuiltinFn(stepwise.spawn))
    |> map.insert("send", r.BuiltinFn(stepwise.send))
}

pub fn boot(source) { 
    // boot might have socket as pids but that's later
    // There is no keyhandler here. that's all client side
    let processes = []
    assert Ok(cont) = stepwise.step(source, prelude(), fn(value) { Ok(stepwise.Done(value)) })
    assert Ok(#(processes, messages, server)) = stepwise.loop(cont, processes, [])
    let processes = deliver_messages(processes, messages)
    let ref = real_js.make_reference(processes)
    // render pids for the client
    // put a debug function in client eval in the client
    // Move everything to harness as used previously
    // Total counter is a nice way to do things
    // Show in client which count you are
    case server {
        r.Function(arg, body, env, _) -> Ok(fn(method, path, body) { 
            let request = r.Record([
                #("method", r.Binary(method)),
                #("path", r.Binary(path)),
                #("body", r.Binary(body)),
            ])
            let processes = real_js.dereference(ref)
            assert Ok(cont) = stepwise.step_call(server, request, fn(value) { Ok(stepwise.Done(value)) })
            assert Ok(#(processes, messages, response)) = stepwise.loop(cont, processes, [])
            let processes = deliver_messages(processes, messages)
            real_js.set_reference(ref, processes)
            // Need to handle variable type
            case response {
                r.Binary(content) -> content 
                r.Function(pattern, body, captured, _self) -> {
                    // TODO HTML heading
                    // create the spawn and send function, this should gather and execute after main function
                    // functions should have hash ref to AST to be serialized. Have to use interpreter until that is ready
                    // builtins should be implement foo: builtin.foo
                    // TODO call interpret in the client
                    // Pass out the pids
                    list.map(map.to_list(captured) |> list.append([#("doo", response)]), r.render_var)
                    // |> list.append([javascript.render_to_string(typed, typer)])
                    |> string.join("\n")   
                }
                _ -> todo("havent handled non binary responses")
            }
        })
        _ -> todo("need to handle other server types")
    }
}


fn deliver_messages(processes, messages) { 
    case messages {
        [] -> processes
        [r.Tuple([r.Pid(i), message]), ..rest] -> {
            let pre = list.take(processes, i)
            let [process, ..post] = list.drop(processes, i)
            // need messages offset
            assert Ok(cont) = stepwise.step_call(process, message, fn(value) { Ok(stepwise.Done(value)) })
            // TODO need function to hadnle messages here
            assert Ok(#([],messages, value)) = stepwise.loop(cont, [], rest)
            let processes = list.flatten([pre, [value], post])
            deliver_messages(processes, messages)
        }
    }
}