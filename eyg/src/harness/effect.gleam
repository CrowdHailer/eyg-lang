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
      io.debug(message)
      r.continue(k, r.unit)
    },
  )
}

pub fn window_alert() {
  #(
    t.Binary,
    t.unit,
    fn(message, k) {
      use message <- cast.string(message)
      window.alert(message)
      r.continue(k, r.unit)
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
      r.continue(k, value)
    },
  )
}

pub fn http() {
  #(
    t.Binary,
    t.unit,
    fn(request, k) {
      use method <- cast.field("method", cast.any, request)
      io.debug(method)
      use scheme <- cast.field("scheme", cast.any, request)
      io.debug(scheme)
      use host <- cast.field("host", cast.string, request)
      io.debug(host)
      use port <- cast.field("port", cast.any, request)
      io.debug(port)
      use path <- cast.field("path", cast.string, request)
      io.debug(path)
      use query <- cast.field("query", cast.any, request)
      io.debug(query)
      use headers <- cast.field("headers", cast.any, request)
      io.debug(headers)
      use body <- cast.field("body", cast.any, request)
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

      r.continue(k, r.Promise(promise))
    },
  )
}

// Needs to be builtin effect not just handler so that correct external handlers can be applied.
pub fn await() {
  #(
    t.Binary,
    t.unit,
    fn(promise, k) {
      use js_promise <- cast.promise(promise)
      r.Async(js_promise, k)
    },
  )
}

pub fn wait() {
  #(
    t.Integer,
    t.unit,
    fn(milliseconds, k) {
      use milliseconds <- cast.integer(milliseconds)
      let p = promisex.wait(milliseconds)
      r.continue(k, r.Promise(promise.map(p, fn(_) { r.unit })))
    },
  )
}
