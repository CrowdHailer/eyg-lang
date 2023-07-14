import gleam/io
import gleam/int
import gleam/map
import gleam/fetch
import gleam/http.{Get}
import gleam/http/request
import gleam/javascript/promise.{try_await}
import eyg/analysis/typ as t
import plinth/browser/window
import plinth/javascript/promisex
import eyg/runtime/interpreter as r
import harness/ffi/cast
import harness/ffi/env

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
      // TODO don;t need env as value doesnt' modify it
      let env = env.empty()
      r.prim(r.Value(r.unit), env, k)
    },
  )
}

pub fn window_alert() {
  #(
    t.Binary,
    t.unit,
    fn(message, k) {
      // use message <- cast.string(message)
      // window.alert(message)
      // r.continue(k, r.unit)
      todo("sn alert")
    },
  )
}

pub fn choose() {
  #(
    t.unit,
    t.boolean,
    fn(message, k) {
      let value = case int.random(0, 2) {
        0 -> r.false
        1 -> r.true
      }
      // r.continue(k, value)
      todo
    },
  )
}

pub fn http() {
  #(
    t.Binary,
    t.unit,
    fn(request, k) {
      let env = env.empty()
      // TODO reinstate ENV
      use method <- cast.require(
        cast.field("method", cast.any, request),
        env,
        k,
      )
      io.debug(method)
      use scheme <- cast.require(
        cast.field("scheme", cast.any, request),
        env,
        k,
      )
      io.debug(scheme)
      use host <- cast.require(cast.field("host", cast.string, request), env, k)
      io.debug(host)
      use port <- cast.require(cast.field("port", cast.any, request), env, k)
      io.debug(port)
      use path <- cast.require(cast.field("path", cast.string, request), env, k)
      io.debug(path)
      use query <- cast.require(cast.field("query", cast.any, request), env, k)
      io.debug(query)
      use headers <- cast.require(
        cast.field("headers", cast.any, request),
        env,
        k,
      )
      io.debug(headers)
      use body <- cast.require(cast.field("body", cast.any, request), env, k)
      io.debug(body)

      let request =
        request.new()
        |> request.set_method(Get)
        |> request.set_host(host)
        |> request.set_path(path)
      let promise =
        try_await(
          fetch.send(request),
          fn(response) { fetch.read_text_body(response) },
        )
        |> promise.map(fn(response) {
          case response {
            Ok(response) -> r.Binary(response.body)
            Error(_) -> r.Binary("bad response")
          }
        })

      r.prim(r.Value(r.Promise(promise)), env, k)
    },
  )
}

// Needs to be builtin effect not just handler so that correct external handlers can be applied.
pub fn await() {
  #(
    t.Binary,
    t.unit,
    fn(promise, k) {
      let env = env.empty()
      // TODO env
      use js_promise <- cast.require(cast.promise(promise), env, k)
      r.prim(r.Async(js_promise, k), env, r.done)
    },
  )
}

pub fn wait() {
  #(
    t.Integer,
    t.unit,
    fn(milliseconds, k) {
      let env = todo("where is env")
      use milliseconds <- cast.require(cast.integer(milliseconds), env, k)
      let p = promisex.wait(milliseconds)
      r.prim(r.Value(r.Promise(promise.map(p, fn(_) { r.unit }))), env, k)
    },
  )
}
