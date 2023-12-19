import gleam/io
import gleam/dynamic
import gleam/int
import gleam/list
import gleam/dict
import gleam/option.{None}
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
import eyg/runtime/interpreter as r
import harness/ffi/cast
import harness/ffi/env
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
  #(
    t.Str,
    t.unit,
    fn(message, k) {
      let env = env.empty()
      let rev = []
      io.print(r.to_string(message))
      io.print("\n")
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

pub fn window_alert() {
  #(
    t.Str,
    t.unit,
    fn(message, k) {
      let env = env.empty()
      let rev = []
      use message <- cast.require(cast.string(message), rev, env, k)
      window.alert(message)
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

pub fn choose() {
  #(
    t.unit,
    t.boolean,
    fn(_, k) {
      let env = env.empty()
      let rev = []
      let value = case int.random(2) {
        0 -> r.false
        1 -> r.true
        _ -> panic as "integer outside expected range"
      }
      r.prim(r.Value(value), rev, env, k)
    },
  )
}

pub fn http() {
  #(
    t.Str,
    t.unit,
    fn(request, k) {
      let env = env.empty()
      let rev = []
      use method <- cast.require(
        cast.field("method", cast.any, request),
        rev,
        env,
        k,
      )
      let assert r.Tagged(method, _) = method
      let method = case string.uppercase(method) {
        "GET" -> http.Get
        "POST" -> http.Post
        _ -> panic as string.concat(["unknown method: ", method])
      }
      use _scheme <- cast.require(
        cast.field("scheme", cast.any, request),
        rev,
        env,
        k,
      )
      use host <- cast.require(
        cast.field("host", cast.string, request),
        rev,
        env,
        k,
      )
      use _port <- cast.require(
        cast.field("port", cast.any, request),
        rev,
        env,
        k,
      )
      use path <- cast.require(
        cast.field("path", cast.string, request),
        rev,
        env,
        k,
      )
      use _query <- cast.require(
        cast.field("query", cast.any, request),
        rev,
        env,
        k,
      )
      use headers <- cast.require(
        cast.field("headers", cast.list, request),
        rev,
        env,
        k,
      )
      let assert Ok(headers) =
        list.try_map(headers, fn(h) {
          use k <- result.try(r.field(h, "key"))
          let assert r.Str(k) = k
          use value <- result.try(r.field(h, "value"))
          let assert r.Str(value) = value

          Ok(#(k, value))
        })

      use body <- cast.require(
        cast.field("body", cast.any, request),
        rev,
        env,
        k,
      )
      // TODO fix binary or string
      let assert r.Str(body) = body

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
                r.ok(
                  r.Record([
                    #("status", r.Integer(response.status)),
                    #(
                      "headers",
                      r.LinkedList(
                        list.map(response.headers, fn(h) {
                          let #(k, v) = h
                          r.Record([#("key", r.Str(k)), #("value", r.Str(v))])
                        }),
                      ),
                    ),
                    #("body", r.Str(response.body)),
                  ]),
                )
              resp
            }

            Error(_) -> r.error(r.Str("bad response"))
          }
        })

      r.prim(r.Value(r.Promise(promise)), rev, env, k)
    },
  )
}

pub fn open() {
  #(
    t.Str,
    t.unit,
    fn(target, k) {
      let env = env.empty()
      let rev = []

      use target <- cast.require(cast.string(target), rev, env, k)
      let p = open_browser(target)
      io.debug(target)
      r.prim(
        r.Value(r.Promise(promise.map(p, fn(_terminate) { r.unit }))),
        rev,
        env,
        k,
      )
    },
  )
}

@external(javascript, "open", "default")
pub fn open_browser(target: String) -> promise.Promise(Nil)

// Needs to be builtin effect not just handler so that correct external handlers can be applied.
pub fn await() {
  #(
    t.Str,
    t.unit,
    fn(promise, k) {
      let env = env.empty()
      let rev = []
      use js_promise <- cast.require(cast.promise(promise), rev, env, k)
      r.prim(r.Async(js_promise, rev, env, k), rev, env, None)
    },
  )
}

pub fn wait() {
  #(
    t.Integer,
    t.unit,
    fn(milliseconds, k) {
      let env = env.empty()
      let rev = []
      use milliseconds <- cast.require(cast.integer(milliseconds), rev, env, k)
      let p = promisex.wait(milliseconds)
      r.prim(r.Value(r.Promise(promise.map(p, fn(_) { r.unit }))), rev, env, k)
    },
  )
}

// Don't need the detail of decoding JSON in EYG as will move away from it.
pub fn read_source() {
  #(
    t.Str,
    t.result(t.Str, t.unit),
    fn(file, k) {
      let env = env.empty()
      let rev = []

      use file <- cast.require(cast.string(file), rev, env, k)
      case simplifile.read(file) {
        Ok(json) ->
          case decode.from_json(json) {
            Ok(exp) ->
              r.prim(
                r.Value(r.ok(r.LinkedList(core.expression_to_language(exp)))),
                rev,
                env,
                k,
              )
            Error(_) -> r.prim(r.Value(r.error(r.unit)), rev, env, k)
          }
        Error(_) -> r.prim(r.Value(r.error(r.unit)), rev, env, k)
      }
    },
  )
}

pub fn file_read() {
  #(
    t.Str,
    t.result(t.Str, t.unit),
    fn(file, k) {
      let env = env.empty()
      let rev = []

      use file <- cast.require(cast.string(file), rev, env, k)
      case simplifile.read(file) {
        Ok(content) -> r.prim(r.Value(r.ok(r.Str(content))), rev, env, k)
        Error(_) -> {
          io.debug(#("failed to read", file))
          r.prim(r.Value(r.error(r.unit)), rev, env, k)
        }
      }
    },
  )
}

pub fn file_write() {
  #(
    t.Str,
    t.unit,
    fn(request, k) {
      let env = env.empty()
      let rev = []
      use file <- cast.require(
        cast.field("file", cast.string, request),
        rev,
        env,
        k,
      )
      use content <- cast.require(
        cast.field("content", cast.string, request),
        rev,
        env,
        k,
      )
      let assert Ok(_) = simplifile.write(content, file)
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

@external(javascript, "../cozo_ffi.js", "load")
fn load(triples: String) -> promise.Promise(Nil)

@external(javascript, "../cozo_ffi.js", "query")
fn run_query(query: String) -> promise.Promise(String)

pub fn load_db() {
  #(
    t.Str,
    t.unit,
    fn(triples, k) {
      let env = env.empty()
      let rev = []
      use triples <- cast.require(cast.string(triples), rev, env, k)
      let p = load(triples)
      r.prim(r.Value(r.Promise(promise.map(p, fn(_) { r.unit }))), rev, env, k)
    },
  )
}

pub fn query_db() {
  #(
    t.Str,
    t.unit,
    fn(query, k) {
      let env = env.empty()
      let rev = []
      use query <- cast.require(cast.string(query), rev, env, k)
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
                        r.Integer(value)
                      },
                      fn(raw) {
                        use value <- result.map(dynamic.string(raw))
                        r.Str(value)
                      },
                      fn(raw) {
                        use value <- result.map(dynamic.list(dynamic.string)(raw,
                        ))
                        r.LinkedList(list.map(value, r.Str))
                      },
                    ]),
                  ),
                ),
              ),
            )
          let assert Ok(#(headers, rows)) = json.decode(raw, decoder)
          list.map(rows, fn(row) {
            let assert Ok(fields) = list.strict_zip(headers, row)
            r.Record(fields)
          })
          |> r.LinkedList
        })

      r.prim(r.Value(r.Promise(p)), rev, env, k)
    },
  )
}

// adm-zip is dependency free
// jszip use packo a port of zlib with other compression
pub fn zip() {
  #(
    t.LinkedList(
      t.Record(t.Extend("name", t.Str, t.Extend("content", t.Str, t.Open(-1)))),
    ),
    t.unit,
    fn(query, k) {
      let env = env.empty()
      let rev = []
      use items <- cast.require(cast.list(query), rev, env, k)
      let assert Ok(items) =
        list.try_map(items, fn(value) {
          use name <- result.then(r.field(value, "name"))
          let assert r.Str(name) = name
          use content <- result.then(r.field(value, "content"))
          let assert r.Str(content) = content

          Ok(#(name, content))
        })

      let zipped = do_zip(array.from_list(items))

      r.prim(r.Value(r.Str(zipped)), rev, env, k)
    },
  )
}

@external(javascript, "../zip_ffi.js", "zip")
fn do_zip(items: Array(#(String, String))) -> String
