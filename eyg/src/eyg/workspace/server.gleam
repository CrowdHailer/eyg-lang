import gleam/dynamic
import gleam/int
import gleam/io
import gleam/map
import gleam/option.{None}
import gleam/string
import eyg/interpreter/interpreter as r
import eyg/interpreter/stepwise

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

fn prelude() { 
    map.new()
    |> map.insert("debug", r.BuiltinFn(io.debug))
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
    let cont = stepwise.step(source, prelude(), fn(value) { stepwise.Done(value) })
    let #(processes, messages, server) = stepwise.loop(cont, processes, [])
    case processes, messages {
        [], [] -> Nil
        _, _ -> todo("finish handling spawning processes on boot") 
    }
    // Deliver first messages
    // Put processes in a reference
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
            let cont = stepwise.step_call(server, request, fn(value) { stepwise.Done(value) })
            let #(processes, messages, response) = stepwise.loop(cont, processes, [])
            case processes, messages {
                [], [] -> Nil
                _, _ -> todo("finish handling spawning processes on serve") 
            }
            // Need to handle variable type
            case response {
                r.Binary(content) -> content 
                _ -> todo("havent handled non binary responses")
            }
        })
        _ -> todo("need to handle other server types")
    }
}