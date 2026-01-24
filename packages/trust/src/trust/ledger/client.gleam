import gleam/http
import gleam/http/request
import gleam/http/response.{Response}
import gleam/json
import spotless/origin
import trust/ledger/schema

pub fn submit_request(endpoint, payload, signature) {
  let #(origin, path) = endpoint

  origin.to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path(path)
  |> request.set_header("content-type", "application/json")
  |> request.set_header("authorization", "Signature " <> signature)
  |> request.set_body(payload)
}

pub fn submit_response(response) {
  let Response(status:, body:, ..) = response
  case status {
    200 -> json.parse_bits(body, schema.archived_decoder())
    _ -> todo
  }
}
