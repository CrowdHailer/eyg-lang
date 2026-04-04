import eyg/hub/publisher
import eyg/hub/schema
import eyg/hub/signatory
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/http/response.{Response}
import gleam/json
import gleam/option.{None, Some}
import multiformats/cid/v1
import ogre/operation.{type Operation}
import untethered/ledger/client
import untethered/substrate

pub fn submit_signatory(
  revision: substrate.Entry(Nil, signatory.Event),
  signature: String,
) -> Operation(BitArray) {
  let payload = signatory.to_bytes(revision)
  let path = "/signatories/submit"
  client.submit_request(path, payload, signature)
}

pub fn submit_signatory_response(
  response: response.Response(BitArray),
) -> Result(schema.ArchivedEntry, client.Failure) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      case json.parse_bits(body, schema.archived_entry_decoder()) {
        Ok(response) -> Ok(response)
        Error(reason) -> Error(client.UnableToDecode(reason:))
      }
    _ -> Error(client.UnexpectedStatus(status:))
  }
}

pub fn pull_signatories(
  parameters: schema.PullParameters,
) -> Operation(BitArray) {
  client.pull_request("/signatories/pull", parameters)
}

pub fn pull_signatories_response(
  response: response.Response(BitArray),
) -> Result(_, client.Failure) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      case json.parse_bits(body, schema.pull_response_decoder()) {
        Ok(response) -> Ok(response)
        Error(reason) -> Error(client.UnableToDecode(reason:))
      }
    _ -> Error(client.UnexpectedStatus(status:))
  }
}

// Create a get module operation
pub fn get_module(cid: v1.Cid) -> Operation(BitArray) {
  operation.get("/modules/" <> v1.to_string(cid))
  |> operation.set_body(<<>>)
}

pub fn get_module_response(
  response: response.Response(BitArray),
) -> Result(option.Option(ir.Node(Nil)), client.Failure) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      case json.parse_bits(body, dag_json.decoder(Nil)) {
        Ok(response) -> Ok(Some(response))
        Error(reason) -> Error(client.UnableToDecode(reason:))
      }
    204 -> Ok(None)
    _ -> Error(client.UnexpectedStatus(status:))
  }
}

/// Create a share module operation
pub fn share_module(module: ir.Node(_)) -> Operation(BitArray) {
  let body = dag_json.to_block(module)
  operation.post("/modules/share")
  |> operation.set_header("content-type", "application/json")
  |> operation.set_body(body)
}

pub fn share_response(
  response: response.Response(BitArray),
) -> Result(v1.Cid, client.Failure) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      case json.parse_bits(body, schema.share_response_decoder()) {
        Ok(response) -> Ok(response)
        Error(reason) -> Error(client.UnableToDecode(reason:))
      }
    _ -> Error(client.UnexpectedStatus(status:))
  }
}

pub fn submit_package(
  revision: publisher.Entry,
  signature: String,
) -> Operation(BitArray) {
  let payload = publisher.to_bytes(revision)
  let path = "/packages/submit"
  client.submit_request(path, payload, signature)
}

pub fn submit_package_response(
  response: response.Response(BitArray),
) -> Result(schema.ArchivedEntry, client.Failure) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      case json.parse_bits(body, schema.archived_entry_decoder()) {
        Ok(response) -> Ok(response)
        Error(reason) -> Error(client.UnableToDecode(reason:))
      }
    _ -> Error(client.UnexpectedStatus(status:))
  }
}
