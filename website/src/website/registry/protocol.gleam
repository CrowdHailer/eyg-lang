import dag_json
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{Request}
import gleam/http/response.{Response}
import gleam/int
import gleam/json
import multiformats/cid/v1
import multiformats/hashes
import spotless/origin
import trust/substrate

pub fn encode(entry: substrate.Entry(Payload)) {
  substrate.entry_encode(entry, payload_encode)
}

pub fn decoder() {
  substrate.entry_decoder(substrate.decode_set(payload_decoders(), _))
}

// TODO call Event or Content or something else
pub type Payload {
  Release(version: Int, module: v1.Cid)
}

// content decoders
pub fn payload_decoders() {
  substrate.DecoderSet(
    [#("release", release_decoder())],
    Release(0, v1.Cid(dag_json.code(), hashes.Multihash(hashes.Sha256, <<>>))),
  )
}

fn release_decoder() {
  use version <- decode.field("version", decode.int)
  use module <- decode.field("module", dag_json.decode_cid())
  decode.success(Release(version:, module:))
}

fn payload_encode(payload) {
  case payload {
    Release(version:, module:) -> {
      let assert Ok(cid) = v1.to_string(module)

      #(
        "release",
        dag_json.object([
          #("version", dag_json.int(version)),
          #("module", dag_json.cid(cid)),
        ]),
      )
    }
  }
}

pub fn pull_events_request(origin, since) {
  origin_to_request(origin)
  |> request.set_path("/registry/events")
  |> request.set_query([#("since", int.to_string(since))])
  |> request.set_body(<<>>)
}

pub type PullEventsResponse {
  PullEventsResponse(events: List(substrate.Entry(Payload)), cursor: Int)
}

fn pull_events_response_decoder() {
  use events <- decode.field("events", decode.list(decoder()))
  use cursor <- decode.field("cursor", decode.int)
  decode.success(PullEventsResponse(events:, cursor:))
}

pub fn pull_events_response_encode(events, cursor) {
  json.object([
    #("cursor", json.int(cursor)),
    #("events", json.array(events, encode)),
  ])
}

pub fn pull_events_response(response) {
  let Response(status:, body:, ..) = response
  case status {
    200 -> json.parse_bits(body, pull_events_response_decoder())
    _ -> todo
  }
}

pub fn fetch_fragment_request(origin, cid) {
  origin_to_request(origin)
  |> request.set_path("/registry/f/" <> cid)
  |> request.set_body(<<>>)
}

pub fn share_request(origin, block: BitArray) {
  origin_to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path("/registry/share")
  |> request.set_header("content-type", "application/json")
  |> request.set_body(block)
}

pub fn share_response(response) {
  let Response(status:, body:, ..) = response
  case status {
    200 -> bit_array.to_string(body)
    _ -> {
      echo response
      todo
    }
  }
}

pub fn publish_request(origin, package_id, version, fragment) {
  // let payload = Release(package_id:, version:, fragment:)
  let json = encode(todo)
  origin_to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path("/registry/submit")
  |> request.set_header("content-type", "application/json")
  |> request.set_body(<<json.to_string(json):utf8>>)
}

pub fn publish_response(response) {
  let Response(status:, body: _, ..) = response
  case status {
    // event number is probably the thing to pull
    200 -> Ok(Nil)
    _ -> todo
  }
}

pub fn origin_to_request(origin) {
  let origin.Origin(scheme:, host:, port:) = origin

  Request(..request.new(), scheme:, host:, port:)
}
