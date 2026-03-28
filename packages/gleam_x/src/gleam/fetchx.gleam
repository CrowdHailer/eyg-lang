import gleam/fetch
import gleam/javascript/promise

pub fn send_bits(request) {
  use response <- promise.try_await(fetch.send_bits(request))
  fetch.read_bytes_body(response)
}
