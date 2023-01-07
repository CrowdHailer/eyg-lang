// serverless
import gleam/io
import gleam/list
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eyg/analysis/inference
import harness/stdlib
import gleam/javascript
import eygir/decode

pub fn cli_build(source) {
  assert r.Value(term) = r.eval(source, todo, r.Value)
  fn(raw) {
    // Need to loop through effects
    r.eval_call(term, r.Binary(raw), r.Value)
  }
}

pub fn run(source, _) {
  let store = javascript.make_reference(source)
  let #(types, values) = stdlib.lib()

  let handle = fn(method, scheme, host, path, query, body) {
    // prog is new on every request could store eval'd in store
    let prog = e.Apply(e.Select("web"), javascript.dereference(store))

    let a =
      inference.infer(
        types,
        prog,
        t.Unbound(-1),
        t.Closed,
        javascript.make_reference(0),
        [],
      )
    // type_of(a, [])
    // |> io.debug()
    server_run(prog, method, scheme, host, path, query, body)
  }

  let save = fn(raw) {
    assert Ok(source) = decode.from_json(raw)
    javascript.set_reference(store, source)
    write_file_sync("saved/saved.json", raw)
    Nil
  }
  do_serve(handle, save)
  // This return type is ignored but should maybe be part of ffi for cli
  0
}

external fn write_file_sync(String, String) -> Nil =
  "fs" "writeFileSync"

fn server_run(prog, method, scheme, host, path, query, body) {
  let #(types, values) = stdlib.lib()
  let request =
    r.Record([
      #("method", r.Binary(method)),
      #("scheme", r.Binary(scheme)),
      #("host", r.Binary(host)),
      #("path", r.Binary(path)),
      #("query", r.Binary(query)),
      #("body", r.Binary(body)),
    ])
  assert return = r.run(prog, values, request, in_cli)
  assert Ok(r.Binary(body)) = r.field(return, "body")
  body
}

external fn do_serve(
  fn(String, String, String, String, String, String) -> String,
  fn(String) -> Nil,
) -> Nil =
  "../entry.js" "serve"

pub fn in_cli(label, term) {
  io.debug(#("Effect", label, term))
  r.Record([])
}
