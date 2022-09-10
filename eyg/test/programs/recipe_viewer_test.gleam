import gleam/io
import gleam/string
import eyg/ast/encode
import eyg/ast/expression as e

import eyg/interpreter/interpreter as r
import eyg/interpreter/effectful
// TODO need an effectful version that allows us to access stuff here
import eyg/interpreter/tail_call


external fn cwd() -> String = "" "process.cwd"
external fn read_file_sync(String, String) -> String = "fs" "readFileSync"

// todo move to global/hash/something suggesting one program
fn load() { 
    let path = string.join([cwd(), "..", "editor", "public", "saved.json"], "/")
    let json = read_file_sync(path, "utf8")
    encode.from_json(encode.json_from_string(json))
}

// ------- Move

pub fn fetching_a_recipe_test()  {
    let program = e.access(load(), "recipe")
    // TODO we can assert that the type is of the correct value
    assert Ok(term) = effectful.eval(program)
    
    // TODO make request a real request
    let request = r.Tuple([])
    assert Ok(r.Effect("HTTP", request, cont)) = tail_call.eval_call(term, request)
    assert r.Tagged("Get", r.Binary(url)) = request
    io.debug(url)
    assert Ok(r.Binary(content)) = cont(r.Binary("stuff"))
    io.debug(content)
    todo("THis is the test")
}