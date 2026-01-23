import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response.{Response}
import gleam/json
import multiformats/base32
import spotless/origin
import trust/protocol

pub fn submit_request(endpoint, payload, signature) {
  let #(origin, path) = endpoint

  origin.to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path(path)
  |> request.set_header("content-type", "application/json")
  |> request.set_header(
    "authorization",
    "Signature " <> base32.encode(signature),
  )
  |> request.set_body(payload)
}

pub fn pull_events_request(endpoint, entity) {
  let #(origin, path) = endpoint

  origin.to_request(origin)
  |> request.set_path(path)
  |> request.set_query([#("entity", entity)])
  |> request.set_body(<<>>)
}

pub fn pull_events_response(response) {
  let Response(status:, body:, ..) = response
  case status {
    200 -> json.parse_bits(body, protocol.pull_events_response_decoder())
    _ -> todo
  }
}

pub fn to_bytes(entity) {
  protocol.encode(entity)
  |> json.to_string
  |> bit_array.from_string
}
