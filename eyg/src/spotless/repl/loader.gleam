import gleam/dict
import gleam/io
import gleam/uri
import gleam/javascript/promise
import gleam/http/request
import gleam/fetch
import plinth/javascript/console
import eygir/decode
import eygir/annotated as a
import eyg/runtime/interpreter/runner as r
import harness/stdlib
import eyg/runtime/cast
import eyg/runtime/break
import eyg/runtime/value as v

pub fn load(src) {
  let assert Ok(req) = request.from_uri(src)
  use response <- promise.try_await(fetch.send(req))
  use response <- promise.map_try(fetch.read_text_body(response))
  let assert Ok(source) = decode.from_json(response.body)
  let source = a.add_annotation(source, Nil)
  case r.execute(source, stdlib.env(), handlers()) {
    Ok(prog) -> {
      let assert Ok(exec) = cast.field("exec", cast.any, prog)
      let assert Error(#(break.UnhandledEffect("Prompt", prompt), Nil, env, k)) =
        r.resume(exec, [v.unit], stdlib.env(), handlers())
      Ok(#(prompt, env, k))
    }
    Error(reason) -> {
      console.log(reason)
      Error(panic as "failed to start")
    }
  }
}

pub fn handlers() {
  dict.new()
}
