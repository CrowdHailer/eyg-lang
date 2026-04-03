import eyg/hub/publisher
import eyg/hub/schema
import eyg/ir/dag_json
import eyg/ir/tree
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response.{Response}
import gleam/json
import gleam/list
import multiformats/cid/v1
import ogre/operation
import ogre/origin
import untethered/ledger/client

// pub fn entries_request(origin: origin.Origin, parameters: schema.PullParameters) {
//   client.entries_request(#(origin, "/registry/entries"), parameters)
// }

// pub fn entries_response(response) {
//   case client.entries_response(response) {
//     Ok(schema.EntriesResponse(entries:)) ->
//       list.try_map(entries, fn(entry) {
//         let assert Ok(event) = json.parse(entry.payload, publisher.decoder())
//         echo entry
//         Ok(#(entry.cursor, event.content))
//       })
//     _ -> todo
//   }
// }

pub fn module(cid: v1.Cid) {
  operation.get("/registry/modules/" <> v1.to_string(cid))
  |> operation.set_body(<<>>)
}

pub fn share(module: tree.Node(_)) -> operation.Operation(BitArray) {
  let body = dag_json.to_block(module)
  operation.post("/registry/share")
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
