import gleam/io
import gleam/int
import gleam/list
import gleam/map
import gleam/option.{None}
import gleam/result
import gleam/string
import gleam/fetch
import gleam/http
import gleam/http/request
import gleam/javascript/promise.{try_await}
import eyg/analysis/typ as t
import plinth/browser/window
import plinth/javascript/promisex
import eyg/runtime/interpreter as r
import harness/ffi/cast
import harness/ffi/env
import plinth/node/fs
import eygir/decode
import harness/ffi/core

pub fn init() {
  #(t.Closed, map.new())
}

pub fn extend(state, label, parts) {
  let #(eff, handlers) = state
  let #(from, to, handler) = parts
  let eff = t.Extend(label, #(from, to), eff)
  let handlers = map.insert(handlers, label, handler)
  #(eff, handlers)
}

pub fn debug_logger() {
  #(
    t.Binary,
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
    t.Binary,
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
      let value = case int.random(0, 2) {
        0 -> r.false
        1 -> r.true
      }
      r.prim(r.Value(value), rev, env, k)
    },
  )
}

pub fn http() {
  #(
    t.Binary,
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
      }
      use scheme <- cast.require(
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
      use port <- cast.require(
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
      use query <- cast.require(
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
        list.try_map(
          headers,
          fn(h) {
            use k <- result.try(r.field(h, "key"))
            let assert r.Binary(k) = k
            use value <- result.try(r.field(h, "value"))
            let assert r.Binary(value) = value

            Ok(#(k, value))
          },
        )

      use body <- cast.require(
        cast.field("body", cast.any, request),
        rev,
        env,
        k,
      )

      let request =
        request.new()
        |> request.set_method(method)
        |> request.set_host(host)
        |> request.set_path(path)
      // TODO decide on option typing
      // |> request.set_query(query)

      let request =
        list.fold(
          headers,
          request,
          fn(req, h) {
            let #(k, v) = h
            request.set_header(req, k, v)
          },
        )

      let promise =
        try_await(
          fetch.send(request),
          fn(response) { fetch.read_text_body(response) },
        )
        |> promise.map(fn(response) {
          case response {
            Ok(response) -> {
              let resp =
                r.ok(r.Record([
                  #("status", r.Integer(response.status)),
                  #(
                    "headers",
                    r.LinkedList(list.map(
                      response.headers,
                      fn(h) {
                        let #(k, v) = h
                        r.Record([
                          #("key", r.Binary(k)),
                          #("value", r.Binary(v)),
                        ])
                      },
                    )),
                  ),
                  #("body", r.Binary(response.body)),
                ]))
              resp
            }

            Error(_) -> r.Binary("bad response")
          }
        })

      r.prim(r.Value(r.Promise(promise)), rev, env, k)
    },
  )
}

pub fn open() {
  #(
    t.Binary,
    t.unit,
    fn(target, k) {
      let env = env.empty()
      let rev = []

      use target <- cast.require(cast.string(target), rev, env, k)
      // io.debug()
      let p = open_browser(target)
      io.debug(target)
      r.prim(
        r.Value(r.Promise(promise.map(
          p,
          fn(terminate) {
            io.debug(terminate)
            r.unit
          },
        ))),
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
    t.Binary,
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
    t.Binary,
    t.result(t.Binary, t.unit),
    fn(file, k) {
      let env = env.empty()
      let rev = []

      use file <- cast.require(cast.string(file), rev, env, k)
      let json = fs.read_file_sync(file)
      case decode.from_json(json) {
        Ok(exp) ->
          r.prim(
            r.Value(r.LinkedList(core.expression_to_language(exp))),
            rev,
            env,
            k,
          )
        Error(_) -> r.prim(r.Value(r.unit), rev, env, k)
      }
    },
  )
}

@external(javascript, "../cozo_ffi.js", "load")
fn load(triples: String) -> promise.Promise(Nil)

@external(javascript, "../cozo_ffi.js", "query")
fn run_query(query: String) -> promise.Promise(String)

pub fn load_db() {
  #(
    t.Binary,
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
    t.Binary,
    t.unit,
    fn(query, k) {
      let env = env.empty()
      let rev = []
      use query <- cast.require(cast.string(query), rev, env, k)
      let p = run_query(query)
      r.prim(r.Value(r.Promise(promise.map(p, r.Binary))), rev, env, k)
    },
  )
}
