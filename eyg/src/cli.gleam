import gleam/io
import gleam/string
import eyg/ast/encode

import eyg/ast/expression as e

import eyg/interpreter/effectful
// TODO need an effectful version that allows us to access stuff here
import eyg/interpreter/tail_call
import gleam/javascript/array
import eyg/interpreter/interpreter as r



// Should we use the node express server 
// is there something clever with cloudflare worker tooling
// maybe I can just use the erlang backend
// erlang backend might well be the way forward here
// who is doing the tooling that means that erlang cli args are nice
// Read through rad

external fn cwd() -> String = "" "process.cwd"
external fn read_file_sync(String, String) -> String = "fs" "readFileSync"

// todo move to global/hash/something suggesting one program
pub fn load() { 
    // TODO path needs to have dots' for cli
    let path = string.join([cwd(), "editor", "public", "saved.json"], "/")
    let json = read_file_sync(path, "utf8")
    encode.from_json(encode.json_from_string(json))
}

pub fn run(args) {
    let args = array.to_list(args)
    io.debug(args)
    case args {
        [path] -> {
            let program = e.access(load(), path)
            // TODO we can assert that the type is of the correct value
            assert Ok(term) = effectful.eval(program)
            io.debug(term)
        }
    }
}

pub fn req(method, path, body) {
    let request = r.Record([#("method", r.Binary(method)),#("path", r.Binary(path)),#("body", r.Binary(body))])
    // called action/fn/lambda/prog/fetch or slate/slabe on outside
    // THere is an API vs compute endpoint
    // Automate deploy from my program
    // Web/GUO/CLI/HMI are all API's
    let program = e.access(load(), "web")
    assert Ok(term) = effectful.eval(program)
    case effectful.eval_call(term, request, effectful.real_log) {
        // TODO return a response type
        // TODO move out of CLI
        Ok(r.Binary(content)) -> {
            content
        }
        Error(reason) -> {
            reason
        }
    }
}