import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response.{Response}
import gleam/json
import gleam/list
import hub/publisher
import multiformats/cid/v1
import spotless/origin
import untethered/ledger/client
import untethered/ledger/schema

pub fn entries_request(origin: origin.Origin, parameters: schema.PullParameters) {
  client.entries_request(#(origin, "/registry/entries"), parameters)
}

pub fn entries_response(response) {
  case client.entries_response(response) {
    Ok(schema.EntriesResponse(entries:)) ->
      list.try_map(entries, fn(entry) {
        let assert Ok(event) = json.parse(entry.payload, publisher.decoder())
        echo entry
        Ok(#(entry.cursor, event.content))
      })
    _ -> todo
  }
}

pub fn fetch_fragment_request(origin, cid: v1.Cid) {
  origin.to_request(origin)
  |> request.set_path("/registry/f/" <> v1.to_string(cid))
  |> request.set_body(<<>>)
}

pub fn share_request(origin, block: BitArray) {
  origin.to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path("/registry/share")
  |> request.set_header("content-type", "application/json")
  |> request.set_body(block)
}

pub fn share_response(response) {
  let Response(status:, body:, ..) = response
  case status {
    200 -> Ok(bit_array.to_string(body))
    _ -> {
      echo response
      todo
    }
  }
}
