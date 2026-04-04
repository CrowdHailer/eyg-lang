import eyg/hub/client
import eyg/ir/tree as ir
import gleam/fetchx
import gleam/javascript/promise
import gleam/option
import gleam/result
import gleam/string
import multiformats/cid/v1
import ogre/operation
import ogre/origin

pub type Client {
  Client(origin: origin.Origin)
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
) -> promise.Promise(Result(option.Option(ir.Node(Nil)), String)) {
  let operation = client.get_module(cid)
  let request = operation.to_request(operation, client.origin)
  use result <- promise.map(fetchx.send_bits(request))
  case result {
    Ok(response) ->
      client.get_module_response(response) |> result.map_error(string.inspect)
    Error(reason) -> Error(string.inspect(reason))
  }
}
