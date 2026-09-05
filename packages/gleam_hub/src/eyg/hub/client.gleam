import eyg/hub/publisher
import eyg/hub/schema
import eyg/hub/signatory
import eyg/ir/car
import eyg/ir/cid as module_cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/http/request.{type Request}
import gleam/http/response.{Response}
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import midas/continuation.{type Continuation as K}
import midas/effect
import multiformats/cid/v1
import ogre/operation.{type Operation}
import ogre/origin
import untethered/ledger/client
import untethered/ledger/schema as lschema
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
) -> Result(Result(schema.ArchivedEntry, String), client.Failure) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      case json.parse_bits(body, schema.archived_entry_decoder()) {
        Ok(response) -> Ok(Ok(response))
        Error(reason) -> Error(client.UnableToDecode(reason:))
      }
    400 | 401 | 403 | 422 ->
      case json.parse_bits(body, schema.failure_decoder()) {
        Ok(reason) -> Ok(Error(reason))
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
pub fn fetch_module_operation(cid: v1.Cid) -> Operation(BitArray) {
  operation.get("/modules/" <> v1.to_string(cid))
  |> operation.set_body(<<>>)
}

pub fn fetch_module_request(cid, origin) {
  fetch_module_operation(cid)
  |> operation.to_request(origin)
}

pub fn fetch_module_response(
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

/// Make a request to fetch a module by its content identifier from a hub.
pub fn fetch_module(
  cid: v1.Cid,
  origin: origin.Origin,
  fetch: effect.Fetch(t),
  hash: effect.Hash(t),
) -> K(t, Result(ir.Node(Nil), String)) {
  let request = fetch_module_request(cid, origin)
  use result <- continuation.then(fetch(request))
  case result {
    Ok(response) ->
      case fetch_module_response(response) {
        Ok(Some(source)) -> {
          use matches <- continuation.then(has_cid(source, cid, hash))
          continuation.return(case matches {
            True -> Ok(source)
            False -> Error("hub returned a module with the wrong content ID")
          })
        }
        Ok(None) -> continuation.return(Error("no module"))
        Error(_) -> continuation.return(Error("bad module lookup"))
      }
    Error(reason) -> continuation.return(Error(string.inspect(reason)))
  }
}

fn has_cid(source, expected, hash) {
  use actual <- continuation.then(
    module_cid.from_tree(source, fn(bytes) { hash(effect.Sha256, bytes) }),
  )
  continuation.return(actual == expected)
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

fn share_bundle_response(response) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      json.parse_bits(body, schema.share_response_decoder())
      |> result.map_error(string.inspect)
    400 | 413 | 415 | 422 ->
      case json.parse_bits(body, schema.failure_decoder()) {
        Ok(reason) -> Error(reason)
        Error(_) -> Error(string.inspect(client.UnexpectedStatus(status:)))
      }
    _ -> Error(string.inspect(client.UnexpectedStatus(status:)))
  }
}

pub fn share_bundle_operation(bundle) -> operation.Operation(BitArray) {
  let #(#(cid, block), dependencies) = bundle
  let assert Ok(body) =
    car.Car(header: car.Header(version: 1, roots: [cid]), blocks: [
      #(cid, block),
      ..dependencies
    ])
    |> car.encode
  operation.post("/modules/share")
  |> operation.set_header("content-type", car.content_type)
  |> operation.set_body(body)
}

pub fn share_bundle_request(bundle, origin) {
  share_bundle_operation(bundle)
  |> operation.to_request(origin)
}

pub fn share_bundle(
  bundle,
  origin: origin.Origin,
  fetch: effect.Fetch(t),
) -> K(t, Result(v1.Cid, String)) {
  let #(#(root, _), _) = bundle
  let request = share_bundle_request(bundle, origin)

  use result <- continuation.then(fetch(request))
  let result = case result {
    Ok(response) ->
      case share_bundle_response(response) {
        Ok(cid) ->
          case cid == root {
            True -> Ok(cid)
            False -> Error("hub returned the wrong shared module ID")
          }

        Error(reason) -> Error(reason)
      }
    Error(reason) -> Error(string.inspect(reason))
  }
  continuation.return(result)
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
) -> Result(Result(schema.ArchivedEntry, String), client.Failure) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      case json.parse_bits(body, schema.archived_entry_decoder()) {
        Ok(response) -> Ok(Ok(response))
        Error(reason) -> Error(client.UnableToDecode(reason:))
      }
    400 | 401 | 403 | 422 ->
      case json.parse_bits(body, schema.failure_decoder()) {
        Ok(reason) -> Ok(Error(reason))
        Error(reason) -> Error(client.UnableToDecode(reason:))
      }
    _ -> Error(client.UnexpectedStatus(status:))
  }
}

pub fn pull_packages_operation(
  parameters: schema.PullParameters,
) -> Operation(BitArray) {
  client.pull_request("/packages/pull", parameters)
}

pub fn pull_packages_request(
  parameters: schema.PullParameters,
  origin: origin.Origin,
) -> Request(BitArray) {
  pull_packages_operation(parameters)
  |> operation.to_request(origin)
}

pub fn pull_packages_response(
  response: response.Response(BitArray),
) -> Result(schema.PullResponse, client.Failure) {
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

pub fn pull_packages(
  parameters: schema.PullParameters,
  origin: origin.Origin,
  fetch: effect.Fetch(t),
) -> K(t, Result(List(schema.ArchivedEntry), String)) {
  let request = pull_packages_request(parameters, origin)

  use result <- continuation.then(fetch(request))
  let result = case result {
    Ok(response) ->
      case pull_packages_response(response) {
        Ok(lschema.PullResponse(entries:)) -> Ok(entries)

        Error(_) -> Error("bad module lookup")
      }
    Error(reason) -> Error(string.inspect(reason))
  }
  continuation.return(result)
}
