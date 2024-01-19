import gleam/io
import gleam/dynamic
import gleam/int
import gleam/list
import gleam/dict
import gleam/result
import gleam/string
import gleam/fetch
import gleam/http
import gleam/http/request
import gleam/javascript/array.{type Array}
import gleam/javascript/promise.{try_await}
import gleam/json
import simplifile
import eyg/analysis/typ as t
import old_plinth/browser/window
import old_plinth/javascript/promisex
import eyg/runtime/value as v
import eyg/runtime/break
import eyg/runtime/cast
import eygir/decode
import harness/ffi/core

pub fn init() {
  #(t.Closed, dict.new())
}

pub fn extend(state, label, parts) {
  let #(eff, handlers) = state
  let #(from, to, handler) = parts
  let eff = t.Extend(label, #(from, to), eff)
  let handlers = dict.insert(handlers, label, handler)
  #(eff, handlers)
}

pub fn debug_logger() {
  #(t.Str, t.unit, fn(message) {
    io.print(v.debug(message))
    io.print("\n")
    Ok(v.unit)
  })
}

pub fn window_alert() {
  #(t.Str, t.unit, fn(message) {
    use message <- result.then(cast.as_string(message))
    window.alert(message)
    Ok(v.unit)
  })
}

pub fn choose() {
  #(t.unit, t.boolean, fn(_) {
    let value = case int.random(2) {
      0 -> v.false
      1 -> v.true
      _ -> panic as "integer outside expected range"
    }
    Ok(value)
  })
}

pub fn http() {
  #(t.Str, t.unit, fn(request) {
    use method <- result.then(cast.field("method", cast.any, request))
    let assert v.Tagged(method, _) = method
    let method = case string.uppercase(method) {
      "GET" -> http.Get
      "POST" -> http.Post
      _ -> panic as string.concat(["unknown method: ", method])
    }
    use _scheme <- result.then(cast.field("scheme", cast.any, request))
    use host <- result.then(cast.field("host", cast.as_string, request))
    use _port <- result.then(cast.field("port", cast.any, request))
    use path <- result.then(cast.field("path", cast.as_string, request))
    use _query <- result.then(cast.field("query", cast.any, request))
    use headers <- result.then(cast.field("headers", cast.as_list, request))
    let assert Ok(headers) =
      list.try_map(headers, fn(h) {
        use k <- result.try(cast.field("key", cast.as_string, h))
        use value <- result.try(cast.field("value", cast.as_string, h))
        Ok(#(k, value))
      })

    use body <- result.then(cast.field("body", cast.any, request))
    // TODO fix binary or string
    let assert v.Str(body) = body

    let request =
      request.new()
      |> request.set_method(method)
      |> request.set_host(host)
      |> request.set_path(path)
      // TODO decide on option typing for query
      // need set query string
      // |> request.set_query(query)
      |> request.set_body(body)

    let request =
      list.fold(headers, request, fn(req, h) {
        let #(k, v) = h
        request.set_header(req, k, v)
      })

    let promise =
      try_await(fetch.send(request), fn(response) {
        fetch.read_text_body(response)
      })
      |> promise.map(fn(response) {
        case response {
          Ok(response) -> {
            let resp =
              v.ok(
                v.Record([
                  #("status", v.Integer(response.status)),
                  #(
                    "headers",
                    v.LinkedList(
                      list.map(response.headers, fn(h) {
                        let #(k, v) = h
                        v.Record([#("key", v.Str(k)), #("value", v.Str(v))])
                      }),
                    ),
                  ),
                  #("body", v.Str(response.body)),
                ]),
              )
            resp
          }

          Error(_) -> v.error(v.Str("bad response"))
        }
      })

    Ok(v.Promise(promise))
  })
}

pub fn open() {
  #(t.Str, t.unit, fn(target) {
    use target <- result.then(cast.as_string(target))
    let p = open_browser(target)
    io.debug(target)
    Ok(v.Promise(promise.map(p, fn(_terminate) { v.unit })))
  })
}

@external(javascript, "open", "default")
pub fn open_browser(target: String) -> promise.Promise(Nil)

// Needs to be builtin effect not just handler so that correct external handlers can be applied.
pub fn await() {
  #(t.Str, t.unit, fn(promise) {
    use js_promise <- result.then(cast.as_promise(promise))
    Error(break.UnhandledEffect("Await", v.Promise(js_promise)))
  })
}

pub fn wait() {
  #(t.Integer, t.unit, fn(milliseconds) {
    use milliseconds <- result.then(cast.as_integer(milliseconds))
    let p = promisex.wait(milliseconds)
    Ok(v.Promise(promise.map(p, fn(_) { v.unit })))
  })
}

// Don't need the detail of decoding JSON in EYG as will move away from it.
pub fn read_source() {
  #(t.Str, t.result(t.Str, t.unit), fn(file) {
    use file <- result.then(cast.as_string(file))
    case simplifile.read(file) {
      Ok(json) ->
        case decode.from_json(json) {
          Ok(exp) -> Ok(v.ok(v.LinkedList(core.expression_to_language(exp))))
          Error(_) -> Ok(v.error(v.unit))
        }
      Error(_) -> Ok(v.error(v.unit))
    }
  })
}

pub fn file_read() {
  #(t.Str, t.result(t.Str, t.unit), fn(file) {
    use file <- result.then(cast.as_string(file))
    case simplifile.read_bits(file) {
      Ok(content) -> Ok(v.ok(v.Binary(content)))
      Error(reason) -> {
        io.debug(#("failed to read", file, reason))
        Ok(v.error(v.unit))
      }
    }
  })
}

pub fn file_write() {
  #(t.Str, t.unit, fn(request) {
    use file <- result.then(cast.field("file", cast.as_string, request))
    use content <- result.then(cast.field("content", cast.as_string, request))
    let assert Ok(_) = simplifile.write(content, file)
    Ok(v.unit)
  })
}

@external(javascript, "../cozo_ffi.js", "load")
fn load(triples: String) -> promise.Promise(Nil)

@external(javascript, "../cozo_ffi.js", "query")
fn run_query(query: String) -> promise.Promise(String)

pub fn load_db() {
  #(t.Str, t.unit, fn(triples) {
    use triples <- result.then(cast.as_string(triples))
    let p = load(triples)
    Ok(v.Promise(promise.map(p, fn(_) { v.unit })))
  })
}

pub fn query_db() {
  #(t.Str, t.unit, fn(query) {
    use query <- result.then(cast.as_string(query))
    let p = run_query(query)

    let p =
      promise.map(p, fn(raw) {
        let decoder =
          dynamic.decode2(
            fn(a, b) { #(a, b) },
            dynamic.field("headers", dynamic.list(dynamic.string)),
            dynamic.field(
              "rows",
              dynamic.list(
                dynamic.list(
                  dynamic.any([
                    fn(raw) {
                      use value <- result.map(dynamic.int(raw))
                      v.Integer(value)
                    },
                    fn(raw) {
                      use value <- result.map(dynamic.string(raw))
                      v.Str(value)
                    },
                    fn(raw) {
                      use value <- result.map(dynamic.list(dynamic.string)(raw))
                      v.LinkedList(list.map(value, v.Str))
                    },
                  ]),
                ),
              ),
            ),
          )
        let assert Ok(#(headers, rows)) = json.decode(raw, decoder)
        list.map(rows, fn(row) {
          let assert Ok(fields) = list.strict_zip(headers, row)
          v.Record(fields)
        })
        |> v.LinkedList
      })

    Ok(v.Promise(p))
  })
}

// adm-zip is dependency free
// jszip use packo a port of zlib with other compression
pub fn zip() {
  #(
    t.LinkedList(
      t.Record(t.Extend(
        "name",
        t.Str,
        t.Extend("content", t.Binary, t.Open(-1)),
      )),
    ),
    t.unit,
    fn(query) {
      use items <- result.then(cast.as_list(query))
      let assert Ok(items) =
        list.try_map(items, fn(value) {
          use name <- result.then(cast.field("name", cast.as_string, value))
          use content <- result.then(cast.field(
            "content",
            cast.as_binary,
            value,
          ))
          Ok(#(name, content))
        })

      let zipped = do_zip(array.from_list(items))
      Ok(v.Str(zipped))
    },
  )
}

@external(javascript, "../zip_ffi.js", "zip")
fn do_zip(items: Array(#(String, BitArray))) -> String
