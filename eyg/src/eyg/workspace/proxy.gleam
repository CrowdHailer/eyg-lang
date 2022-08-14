import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/string
import eyg/ast/encode.{JSON}
import gleam/javascript/promise.{Promise}
import eyg/typer/monotype as t
import eyg/interpreter/interpreter as r


external fn fetch_json(String) -> Promise(Result(JSON, String)) =
  "../../browser_ffi.js" "fetchJSON"

external fn post_json(String, JSON) -> Promise(Result(#(), String)) =
  "../../browser_ffi.js" "postJSON"

const client_id = "123456";
const api = "http://localhost:8080";

fn loop(url) { 
    io.debug("ready")
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
                io.debug(request)

                assert Ok(#(response_id, parts)) = list.key_pop(parts, "response_id")
                assert response_id = encode.assert_string(response_id)
                let reply = encode.object([#("status", encode.integer(200)), #("body", encode.string("Hello"))])
                let url = string.join([api, "response", response_id], "/")
                post_json(url, reply)
                Nil
            }
            Error(_) -> Nil
        }
        loop(url)
    })
}
pub fn run() {
    let url = string.join([api, "request", client_id], "/")
    loop(url)
}

const request_type = t.Record([
    #("method", t.Binary),
    #("path", t.Binary),
    #("body", t.Binary),
], None)
const response_type = t.Record([
    #("status", t.Native("Int", [])),
    #("body", t.Binary),
], None)

pub fn constraint() {    
    t.Native("Run", [t.Function(request_type, response_type)])
}