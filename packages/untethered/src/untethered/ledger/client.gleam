import gleam/http
import gleam/http/request
import gleam/http/response.{Response}
import gleam/json
import ogre/origin
import untethered/ledger/schema

pub type Failure {
  // Protocol Errors
  UnexpectedStatus(status: Int)
  UnableToDecode(reason: json.DecodeError)
}

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
    200 ->
      case json.parse_bits(body, schema.archived_entry_decoder()) {
        Ok(response) -> Ok(response)
        Error(reason) -> Error(UnableToDecode(reason:))
      }
    _ -> Error(UnexpectedStatus(status:))
  }
}

pub fn entries_request(endpoint, parameters) {
  let #(origin, path) = endpoint

  origin.to_request(origin)
  |> request.set_path(path)
  |> request.set_query(schema.pull_parameters_to_query(parameters))
  |> request.set_body(<<>>)
}

pub fn entries_response(response) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      case json.parse_bits(body, schema.entries_response_decoder()) {
        Ok(response) -> Ok(response)
        Error(reason) -> Error(UnableToDecode(reason:))
      }
    _ -> Error(UnexpectedStatus(status:))
  }
}
