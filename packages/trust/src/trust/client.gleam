import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response.{Response}
import gleam/json
import multiformats/base32
import spotless/origin
import trust/protocol/signatory

pub fn pull_events_request(endpoint, entity) {
  let #(origin, path) = endpoint

  origin.to_request(origin)
  |> request.set_path(path)
  |> request.set_query([#("entity", entity)])
  |> request.set_body(<<>>)
}
