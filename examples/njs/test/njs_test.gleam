import compile
import gleam/dynamic
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import gleam/string
import gleeunit
import javascript/mutable_reference as reference
import njs/host
import plinthx/javascript/foreign
import plinthx/javascript/module
import simplifile

pub fn main() {
  gleeunit.main()
}

fn object(fields) {
  foreign.object(array.from_list(fields))
}

fn compiled() {
  let assert Ok(code) = simplifile.read("handler.eyg")
  let assert Ok(output) = compile.compile(code)
  let assert Ok(cwd) = simplifile.current_directory()
  let path = cwd <> "/build/handler-test.mjs"
  let assert Ok(_) = simplifile.write(path, output)
  use loaded <- promise.map(module.load(path))
  let assert Ok(loaded) = loaded
  foreign.property(loaded, "default")
}

fn check(method) {
  use api <- promise.await(compiled())
  let logged = reference.new([])
  let asked = reference.new([])
  let returned = reference.new(#(0, ""))
  let incoming =
    object([
      #("method", dynamic.string(method)),
      #("uri", dynamic.string("/a/b")),
      #(
        "headersIn",
        object([
          #("host", dynamic.string("local")),
          #("accept", dynamic.string("text/plain")),
        ]),
      ),
      #(
        "log",
        foreign.to_dynamic(fn(text) {
          reference.set(logged, [text, ..reference.get(logged)])
          Nil
        }),
      ),
      #(
        "subrequest",
        foreign.to_dynamic(fn(path) {
          let assert Ok(path) = decode.run(path, decode.string)
          reference.set(asked, [path, ..reference.get(asked)])
          promise.resolve(
            object([
              #("status", dynamic.int(200)),
              #("responseText", dynamic.string("from " <> path)),
            ]),
          )
        }),
      ),
      #(
        "return",
        foreign.to_dynamic(fn(status, body) {
          reference.set(returned, #(status, body))
          Nil
        }),
      ),
    ])
  use _ <- promise.map(host.handle(api, incoming))
  #(reference.get(returned), reference.get(logged), reference.get(asked))
}

pub fn a_get_logs_awaits_upstream_and_returns_the_eyg_reply_test() {
  use response <- promise.map(check("GET"))
  assert response
    == #(
      #(200, "EYG handled 2 headers, path /a/b. Upstream said: from /upstream"),
      [dynamic.string("2 headers, path /a/b")],
      ["/upstream"],
    )
}

pub fn other_methods_log_and_return_405_without_subrequests_test() {
  use response <- promise.map(check("POST"))
  assert response
    == #(
      #(405, "Only GET is handled by EYG"),
      [dynamic.string("2 headers, path /a/b")],
      [],
    )
}

pub fn invalid_programs_do_not_compile_test() {
  let assert Error(_) = compile.compile("!int_add(1, \"x\")")
  let assert Error(_) = compile.compile("let =")
  let assert Ok(source) = simplifile.read("handler.eyg")
  let assert Ok(compiled) = compile.compile(source)
  assert !string.contains(compiled, "{ throw \"")
}
