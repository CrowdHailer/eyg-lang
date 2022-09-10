import gleam/dynamic.{Dynamic}
import gleam/int
import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None}
import gleam/string
import eyg/ast/encode.{JSON}
import gleam/javascript/promise.{Promise}
import eyg/typer/monotype as t
import eyg/interpreter/interpreter as r
import eyg/interpreter/effectful
import eyg/interpreter/tail_call
import eyg/ast/expression as e


external fn fetch_json(String) -> Promise(Result(JSON, String)) =
  "../../browser_ffi.js" "fetchJSON"

external fn post_json(String, JSON) -> Promise(Result(#(), String)) =
  "../../browser_ffi.js" "postJSON"

const client_id = "123456";
const api = "http://localhost:8080";


pub fn handle(fetched, state: State) {
    case fetched {
        Ok(#(request, response_id)) -> {
            assert r.Record([#("method", r.Binary(method)),#("path", r.Binary(path)),#("body", r.Binary(body))]) = request
            case string.split(path, "/") {
                // Need to pull this out of the fields value
                // ["", "123456", "_", pid] -> {
                //     let #(function, processes) = state
                //     assert Ok(pid) = int.parse(pid)
                //     assert Ok(processes) = actor.deliver_messages(processes, [r.Tuple([r.Pid(pid), r.Binary(body)])])
                //     let reply = encode.object([#("status", encode.integer(200)), #("body", encode.string("piddy"))])
                //     let url = string.join([api, "response", response_id], "/")
                //     post_json(url, reply)
                //     state

                // }
                ["", "123456", ..path] -> {
                    let path = string.join(path, "/")
                    let request = r.Record([#("method", r.Binary(method)),#("path", r.Binary(path)),#("body", r.Binary(body))])
                    // todo("boooooooooo")
                    // let #(function, processes) = state
                    // assert Ok(#(value, spawned, dispatched)) = actor.eval_call(function, request, list.length(processes), processes, [])
                    // let processes = list.append(processes, spawned)
                    // assert Ok(processes) = actor.deliver_messages(processes, dispatched)
                    // let state = #(function, processes)
                    // // TODO have counter that forwards to logger, build a handle request function that is tested
                    // // 
                    // assert r.Binary(content) = value
                    assert Ok(state) = state
                    assert Ok(term) = effectful.eval(state)
                    case effectful.eval_call(term, request, effectful.real_log) {
                        Ok(r.Binary(content)) -> {
                            let reply = encode.object([#("status", encode.integer(200)), #("body", encode.string(content))])
                            let url = string.join([api, "response", response_id], "/")
                            post_json(url, reply)
                            Ok(state)
                        }
                        Error(reason) -> {
                            let reply = encode.object([#("status", encode.integer(500)), #("body", encode.string(reason))])
                            let url = string.join([api, "response", response_id], "/")
                            post_json(url, reply)
                            Ok(state)
                        }
                    }

                }
            }
        } 
        Error("204") -> {
            state
        }
        Error(reason) -> {
            io.debug(reason)
            state
        }
    }
}

pub fn fetch_request()  {
    let url = string.join([api, "request", client_id], "/")
        promise.map(fetch_json(url), fn(fetched) {
        case fetched {
            Ok(json) -> {
                // TODO put query into path
                let parts = encode.entries(json)
                assert Ok(#(method, parts)) = list.key_pop(parts, "method")
                assert method = encode.assert_string(method)
                assert Ok(#(path, parts)) = list.key_pop(parts, "path")
                assert path = encode.assert_string(path)
                assert Ok(#(body, parts)) = list.key_pop(parts, "body")
                assert body = encode.assert_string(body)
                let request = r.Record([#("method", r.Binary(method)),#("path", r.Binary(path)),#("body", r.Binary(body))])

                assert Ok(#(response_id, parts)) = list.key_pop(parts, "response_id")
                assert response_id = encode.assert_string(response_id)

                Ok(#(request, response_id))
            }
            Error(reason) -> Error(reason)
        }
    })
}

const request_type = t.Record([
    #("method", t.Binary),
    #("path", t.Binary),
    #("body", t.Binary),
], None)
const response_type = t.Record([
    #("status", t.Native("Integer", [])),
    #("body", t.Binary),
], None)

pub fn constraint() {    
    // Function t.put handler
    // TODO put back response type, needs native int in the environment
    // Can I build up and AST e.let_(std, stdlib, prog)?
    t.Function(request_type, t.Binary, t.Union([
        #("Log", t.Function(t.Binary, t.Tuple([]), t.Union([], None))),
        #("HTTP", t.Function(t.Union([#("Get", t.Binary)], None), t.Binary, t.empty))
    ], None))
}

pub type State = Result(#(Dynamic, e.Node(Dynamic, Dynamic)), String)

pub fn code_update(source, key) -> State  {
    io.debug("code update")
    io.debug(key)
    let source = e.access(source, key)
    Ok(source)
}

