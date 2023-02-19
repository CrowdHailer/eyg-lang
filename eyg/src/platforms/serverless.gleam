import gleam/io
import gleam/nodejs/fs
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eyg/analysis/inference
import harness/stdlib
import harness/effect
import gleam/javascript
import eygir/decode
import eyg/runtime/standard

pub fn run(source, _) {
  let store = javascript.make_reference(source)
  let #(types, _values) = stdlib.lib()

  let handle = fn(method, scheme, host, path, query, body) {
    // prog is new on every request could store eval'd in store
    let prog = e.Apply(e.Select("web"), javascript.dereference(store))

    let inferred = inference.infer(types, prog, standard.web, t.Closed)
    case inference.sound(inferred) {
      Ok(Nil) -> Nil
      Error(reason) -> {
        io.debug("not sound")
        io.debug(reason)
        Nil
      }
    }

    server_run(prog, method, scheme, host, path, query, body)
  }

  let save = fn(raw) {
    assert Ok(source) = decode.from_json(raw)
    // should we infer on save
    javascript.set_reference(store, source)
    fs.write_file_sync("saved/saved.json", raw)
    Nil
  }
  do_serve(handle, save)
  // This return type is ignored but should maybe be part of ffi for cli
  // 0
}

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
}

fn server_run(prog, method, scheme, host, path, query, body) {
  let #(_types, values) = stdlib.lib()
  let request =
    r.Record([
      #("method", r.Binary(method)),
      #("scheme", r.Binary(scheme)),
      #("host", r.Binary(host)),
      #("path", r.Binary(path)),
      #("query", r.Binary(query)),
      #("body", r.Binary(body)),
    ])
  assert Ok(return) =
    r.run(
      prog,
      values,
      request,
      handlers().1,
      fn(_, _) { todo("i have type info") },
    )
  assert Ok(r.Binary(body)) = r.field(return, "body")
  body
}

external fn do_serve(
  fn(String, String, String, String, String, String) -> String,
  fn(String) -> Nil,
) -> Nil =
  "../entry.js" "serve"
