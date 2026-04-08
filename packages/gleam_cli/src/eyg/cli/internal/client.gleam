import eyg/cli/internal/crypto
import eyg/cli/internal/store
import eyg/hub/client
import eyg/hub/publisher
import eyg/hub/signatory
import eyg/ir/tree as ir
import gleam/fetchx
import gleam/javascript/promise
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import ogre/operation
import ogre/origin
import untethered/keypair
import untethered/ledger/schema
import untethered/substrate

pub type Client {
  Client(origin: origin.Origin)
}

pub fn initialise_principal(keypair, client: Client) {
  let keypair.Keypair(key_id:, ..) = keypair
  let entry = signatory.first(key_id)
  let payload = signatory.to_bytes(entry)
  let signature = crypto.sign(payload, keypair)
  let operation = client.submit_signatory(entry, signature)
  let request = operation.to_request(operation, client.origin)
  use result <- promise.map(fetchx.send_bits(request))
  case result {
    Ok(response) ->
      client.submit_signatory_response(response)
      |> result.map_error(string.inspect)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pull_principal(client: Client) {
  let operation = client.pull_signatories(schema.pull_parameters())
  let request = operation.to_request(operation, client.origin)
  use result <- promise.map(fetchx.send_bits(request))
  case result {
    Ok(response) ->
      client.pull_signatories_response(response)
      |> result.map_error(string.inspect)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn share_module(
  source: ir.Node(_),
  client: Client,
) -> promise.Promise(Result(v1.Cid, String)) {
  let operation = client.share_module(source)
  let request = operation.to_request(operation, client.origin)
  use result <- promise.map(fetchx.send_bits(request))
  case result {
    Ok(response) ->
      client.share_response(response) |> result.map_error(string.inspect)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn get_module(
  cid: v1.Cid,
  client: Client,
) -> promise.Promise(Result(Option(ir.Node(Nil)), String)) {
  let operation = client.get_module(cid)
  let request = operation.to_request(operation, client.origin)
  use result <- promise.map(fetchx.send_bits(request))
  case result {
    Ok(response) ->
      client.get_module_response(response) |> result.map_error(string.inspect)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn submit_release(
  signatory: store.Signatory,
  package: String,
  module: v1.Cid,
  previous: Option(#(Int, v1.Cid)),
  client: Client,
) -> promise.Promise(Result(schema.ArchivedEntry, String)) {
  let #(sequence, previous) = case previous {
    Some(#(sequence, cid)) -> #(sequence + 1, Some(cid))
    None -> #(1, None)
  }
  let version = sequence
  let store.Signatory(alias: _, principal:, keypair:) = signatory

  let entry =
    substrate.Entry(
      sequence:,
      previous:,
      signatory: principal,
      key: keypair.key_id,
      content: publisher.Release(package:, version:, module:),
    )
  let payload = publisher.to_bytes(entry)
  let signature = crypto.sign(payload, keypair)
  let operation = client.submit_package(entry, signature)
  let request = operation.to_request(operation, client.origin)
  use result <- promise.map(fetchx.send_bits(request))
  case result {
    Ok(response) ->
      client.submit_package_response(response)
      |> result.map_error(string.inspect)
      |> result.flatten
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pull_package(client: Client, package) {
  let parameters =
    schema.PullParameters(since: 0, limit: 1000, entities: [package])
  let operation = client.pull_packages(parameters)
  let request = operation.to_request(operation, client.origin)
  use result <- promise.map(fetchx.send_bits(request))
  case result {
    Ok(response) ->
      client.pull_signatories_response(response)
      |> result.map_error(string.inspect)
    Error(reason) -> Error(string.inspect(reason))
  }
}
