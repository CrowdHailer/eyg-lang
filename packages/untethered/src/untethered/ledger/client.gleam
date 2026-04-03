import gleam/http/response.{Response}
import gleam/json
import ogre/operation
import untethered/ledger/schema

pub type Failure {
  // Protocol Errors
  UnexpectedStatus(status: Int)
  UnableToDecode(reason: json.DecodeError)
}

pub fn submit_request(path, payload, signature) {
  operation.post(path)
  |> operation.set_header("content-type", "application/json")
  |> operation.set_header("authorization", "Signature " <> signature)
  |> operation.set_body(payload)
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

pub fn pull_request(path, parameters) {
  operation.get(path)
  |> operation.set_query(schema.pull_parameters_to_query(parameters))
  |> operation.set_body(<<>>)
}

pub fn pull_response(response) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      case json.parse_bits(body, schema.pull_response_decoder()) {
        Ok(response) -> Ok(response)
        Error(reason) -> Error(UnableToDecode(reason:))
      }
    _ -> Error(UnexpectedStatus(status:))
  }
}
