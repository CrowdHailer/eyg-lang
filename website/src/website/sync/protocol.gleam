import dag_json
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{Request}
import gleam/http/response.{Response}
import gleam/int
import gleam/json
import multiformats/cid/v1
import spotless/origin

pub const release_published = "release_published"

pub type Payload {
  ReleasePublished(package_id: String, version: Int, fragment: String)
}

pub fn payload_decoder() {
  use package_id <- decode.field("package_id", decode.string)
  use version <- decode.field("version", decode.int)
  use fragment <- decode.field("fragment", dag_json.decode_cid())
  let assert Ok(fragment) = v1.to_string(fragment)
  decode.success(ReleasePublished(package_id:, version:, fragment:))
}

pub fn payload_encode(payload) {
  case payload {
    ReleasePublished(package_id:, version:, fragment:) -> {
      dag_json.object([
        #("type", dag_json.string(release_published)),
        #("package_id", dag_json.string(package_id)),
        #("version", dag_json.int(version)),
        #("fragment", dag_json.cid(fragment)),
      ])
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
  PullEventsResponse(events: List(Payload), cursor: Int)
}

pub fn pull_events_response(response) {
  let Response(status:, body:, ..) = response
  case status {
    200 ->
      json.parse_bits(body, {
        use events <- decode.field("events", decode.list(payload_decoder()))
        use cursor <- decode.field("cursor", decode.int)
        decode.success(PullEventsResponse(events:, cursor:))
      })
    _ -> todo
  }
}

pub fn decode_events(body) {
  json.parse(body, {
    use events <- decode.field("events", decode.list(payload_decoder()))
    decode.success(events)
  })
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
  let payload = ReleasePublished(package_id:, version:, fragment:)
  let json = payload_encode(payload)
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
