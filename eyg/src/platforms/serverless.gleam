import gleam/io
import plinth/nodejs/fs
import gleam/javascript/promise.{Promise}
import eygir/expression as e
import eyg/runtime/interpreter as r
import harness/stdlib
import harness/effect
import gleam/javascript
import eygir/decode

pub fn run(source, _) {
  let store = javascript.make_reference(source)
  // let #(types, _values) = stdlib.lib()

  // prog is new on every request could store eval'd in store
  // let prog = e.Apply(e.Select("web"), javascript.dereference(store))

  // let inferred = inference.infer(types, prog, standard.web(), t.Closed)
  // Inference is just handled on page load
  // case inference.sound(inferred) {
  //   Ok(Nil) -> Nil
  //   Error(reason) -> {
  //     io.debug("not sound")
  //     io.debug(reason)
  //     Nil
  //   }
  // }
  let handle = fn(method, scheme, host, path, query, body) {
    // Need to get prog on every run so it's fetch in development
    // Maybe inference belongs on save
    let prog = e.Apply(e.Select("web"), javascript.dereference(store))

    server_run(prog, method, scheme, host, path, query, body)
  }

  let save = fn(raw) {
    let assert Ok(source) = decode.from_json(raw)
    // should we infer on save
    javascript.set_reference(store, source)
    fs.write_file_sync("saved/saved.json", raw)
    Nil
  }
  do_serve(handle, save)
  // This return type is ignored but should maybe be part of ffi for cli
  // 0
  promise.resolve(0)
}

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("HTTP", effect.http())
  |> effect.extend("Await", effect.await())
  |> effect.extend("Wait", effect.wait())
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
  let env = r.Env([], values)
  use ret <- promise.map(r.run_async(prog, env, request, handlers().1))
  case ret {
    Ok(return) ->
      case r.field(return, "body") {
        Ok(r.Binary(body)) -> body
        Ok(_) -> "body field was not a Binary"
        Error(_) -> "return value was not a record"
      }
    Error(reason) -> {
      io.debug(reason)
      "Failed to run serverless program"
    }
  }
}

external fn do_serve(
  fn(String, String, String, String, String, String) -> Promise(String),
  fn(String) -> Nil,
) -> Nil =
  "../entry.js" "serve"
