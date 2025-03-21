// Harness components merge type and runtime so cannot be put in either of those libraries
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/fetch
import gleam/javascript/promise
import gleam/result
import gleam/string
import website/harness/http

pub const l = "Fetch"

pub fn lift() {
  http.request()
}

pub fn lower() {
  t.result(http.response(), t.String)
}

pub fn blocking(lift) {
  use request <- result.map(http.request_to_gleam(lift))
  promise.map(do(request), result_to_eyg)
}

pub fn preflight(lift) {
  use request <- result.try(http.request_to_gleam(lift))
  Ok(fn() { promise.map(do(request), result_to_eyg) })
}

pub fn handle(lift) {
  use p <- result.map(blocking(lift))
  v.Promise(p)
}

pub fn do(request) {
  use response <- promise.try_await(fetch.send_bits(request))
  fetch.read_bytes_body(response)
}

pub fn result_to_eyg(result) {
  case result {
    Ok(response) -> v.ok(http.response_to_eyg(response))
    Error(reason) -> v.error(v.String(string.inspect(reason)))
  }
}

pub fn task_to_eyg(task) {
  v.Promise(promise.map(task, result_to_eyg))
}
