import eyg/runtime/value as v
import gleam/fetch
import gleam/javascript/promise
import gleam/string
import harness/http

pub fn handle(lift) {
  case http.request_to_gleam(lift) {
    Ok(request) -> Ok(task_to_eyg(do(request)))
    Error(reason) -> Error(reason)
  }
}

pub fn do(request) {
  use response <- promise.try_await(fetch.send_bits(request))
  fetch.read_bytes_body(response)
}

pub fn task_to_eyg(task) {
  v.Promise({
    use result <- promise.map(task)
    case result {
      Ok(response) -> v.ok(http.response_to_eyg(response))
      Error(reason) -> v.error(v.Str(string.inspect(reason)))
    }
  })
}
