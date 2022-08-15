import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/string
import eyg/ast/encode.{JSON}
import gleam/javascript/promise.{Promise}
import eyg/typer/monotype as t
import eyg/interpreter/interpreter as r
import eyg/interpreter/actor
import eyg/ast/expression as e


external fn fetch_json(String) -> Promise(Result(JSON, String)) =
  "../../browser_ffi.js" "fetchJSON"

external fn post_json(String, JSON) -> Promise(Result(#(), String)) =
  "../../browser_ffi.js" "postJSON"

const client_id = "123456";
const api = "http://localhost:8080";

fn loop(url, state) { 
    promise.then(fetch_json(url), fn(fetched) {
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
                let #(function, processes) = state
                assert Ok(#(value, spawned, dispatched)) = actor.eval_call(function, request, list.length(processes), [], [])
                let processes = list.append(processes, spawned)
                assert Ok(processes) = actor.deliver_messages(processes, dispatched)
                let state = #(function, processes)
                // TODO have counter that forwards to logger, build a handle request function that is tested
                assert r.Binary(content) = value
                |> io.debug

                assert Ok(#(response_id, parts)) = list.key_pop(parts, "response_id")
                assert response_id = encode.assert_string(response_id)
                let reply = encode.object([#("status", encode.integer(200)), #("body", encode.string(content))])
                let url = string.join([api, "response", response_id], "/")
                post_json(url, reply)
                Nil
            }
            Error(_) -> Nil
        }
        loop(url, state)
    })
}
// pub fn run(state) {
//     io.debug("loaded")
//     let url = string.join([api, "request", client_id], "/")
//     loop(url, state)
// }

pub fn handle(fetched, state) {
    case fetched {
        Ok(#(request, response_id)) -> {
            let #(function, processes) = state
            assert Ok(#(value, spawned, dispatched)) = actor.eval_call(function, request, list.length(processes), [], [])
            let processes = list.append(processes, spawned)
            assert Ok(processes) = actor.deliver_messages(processes, dispatched)
            let state = #(function, processes)
            // TODO have counter that forwards to logger, build a handle request function that is tested
            assert r.Binary(content) = value
            |> io.debug

            let reply = encode.object([#("status", encode.integer(200)), #("body", encode.string(content))])
            let url = string.join([api, "response", response_id], "/")
            post_json(url, reply)
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
    t.Native("Run", [t.Function(request_type, t.Native("Run", [t.Binary]))])
}

pub fn code_update(source, key)  {
    let source = e.access(source, key)
    actor.run_source(source, [])
}