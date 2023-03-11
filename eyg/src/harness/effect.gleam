import gleam/io
import gleam/map
import gleam/fetch
import gleam/http.{Get}
import gleam/http/request
import gleam/http/response
import gleam/javascript/promise.{try_await}
import eyg/analysis/typ as t
import plinth/browser/window
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

pub fn http() {
  #(
    t.Binary,
    t.unit,
    fn(request, k) {
      use method <- cast.field("method", cast.any, request)
      use scheme <- cast.field("scheme", cast.any, request)
      use host <- cast.field("host", cast.string, request)
      use port <- cast.field("port", cast.any, request)
      use path <- cast.field("path", cast.string, request)
      use query <- cast.field("query", cast.any, request)
      use headers <- cast.field("headers", cast.any, request)
      use body <- cast.field("body", cast.any, request)

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
          |> r.Value
        })

      // This is not handled at the point where we are back
      // And I think that this might even make sense because we are handling HTTP outside of async
      // And technically the handler doesn't see that
      // I need some foo raise bar tests inside or outside handler
      // HTTP could be Async from the start
      // perform Async(_ -> perform HTTP)
      // capture async makes promise available
      // Can do the oposite and have promise straight away
      // I'm pretty sure this is right because Logs in a handler should be visible outside.
      // But I want to catch HTTP two efffects one time.
      // r.Async(promise, k)
      r.continue(k, r.Promise(promise))
    },
  )
  // capturing async needs the value to be already ready
  // use message <- cast.string(message)
  // window.alert(message)
  // r.continue(k, r.unit)
}

// Await makes async polymorphic TODO problem
pub fn await() {
  #(
    t.Binary,
    t.unit,
    fn(promise, k) {
      use js_promise <- cast.promise(promise)
      r.Async(js_promise, k)
    },
  )
  // r.Abort(r.UndefinedVariable("omg I'm so lost"))
}
// TODO serialize to return a promise that can be awaited on.
// Now is a function that can error if promise not resolved
// Capturing HTTP can return a value that is not a promise and so await stays sync
