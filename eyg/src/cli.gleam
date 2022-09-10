import gleam/io
import gleam/string
import eyg/ast/encode

import eyg/ast/expression as e

import eyg/interpreter/effectful
// TODO need an effectful version that allows us to access stuff here
import eyg/interpreter/tail_call
import gleam/javascript/array


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
    let path = string.join([cwd(), "..", "editor", "public", "saved.json"], "/")
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