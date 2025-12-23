import eyg/ir/dag_json
import gleam/http/response
import gleam/json
import website/sync/protocol

pub fn pull_events_response(events, cursor) {
  let body =
    json.object([
      #("events", json.array(events, protocol.payload_encode)),
      #("cursor", json.int(cursor)),
    ])
    |> json.to_string
  response.new(200)
  |> response.set_body(<<body:utf8>>)
}

pub fn fetch_fragment_response(source) {
  response.new(200)
  |> response.set_body(dag_json.to_block(source))
}
