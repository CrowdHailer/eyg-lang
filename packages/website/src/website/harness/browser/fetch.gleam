// Harness components merge type and runtime so cannot be put in either of those libraries
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/fetch as gfetch
import gleam/javascript/promise
import gleam/result
import gleam/string
import touch_grass/fetch
import website/harness/http

pub const l = "Fetch"

pub fn lift() {
  http.request()
}

pub fn lower() {
  t.result(http.response(), t.String)
}

pub fn run(request) {
  promise.map(do(request), fn(result) {
    result
    |> result.map_error(string.inspect)
    |> fetch.encode
  })
}

pub fn blocking(lift) {
  use request <- result.map(fetch.decode(lift))
  run(request)
}

pub fn preflight(lift) {
  use request <- result.try(fetch.decode(lift))
  Ok(fn() { run(request) })
}

pub fn handle(lift) {
  use p <- result.map(blocking(lift))
  v.Promise(p)
}

pub fn do(request) {
  use response <- promise.try_await(gfetch.send_bits(request))
  gfetch.read_bytes_body(response)
}

pub fn task_to_eyg(task) {
  v.Promise(promise.map(task, fetch.encode))
}
