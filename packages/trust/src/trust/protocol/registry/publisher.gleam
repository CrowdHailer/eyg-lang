import dag_json
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response.{Response}
import gleam/json
import gleam/option.{None}
import multiformats/cid/v1
import multiformats/hashes
import spotless/origin
import trust/decoder_set
import trust/substrate

pub fn first(signatory, key, package, module) -> Entry {
  substrate.Entry(
    sequence: 1,
    previous: None,
    signatory:,
    key:,
    content: Release(package:, version: 1, module:),
  )
}

pub type Entry =
  substrate.Delegated(Event)

pub fn encode(entry: Entry) {
  substrate.delegated_encode(entry, payload_encode)
}

pub fn decoder() {
  substrate.delegated_decoder(event_decoder())
}

pub fn to_bytes(entry) {
  substrate.to_bytes(encode(entry))
}

pub type Event {
  Release(package: String, version: Int, module: v1.Cid)
}

pub fn event_decoder() {
  let set =
    decoder_set.DecoderSet(
      [#("release", release_decoder())],
      Release(
        "",
        0,
        v1.Cid(dag_json.code(), hashes.Multihash(hashes.Sha256, <<>>)),
      ),
    )
  decoder_set.to_decoder(set, _)
}

fn release_decoder() {
  use package <- decode.field("package", decode.string)
  use version <- decode.field("version", decode.int)
  use module <- decode.field("module", dag_json.decode_cid())
  decode.success(Release(package:, version:, module:))
}

fn payload_encode(payload) {
  case payload {
    Release(package:, version:, module:) -> {
      let assert Ok(cid) = v1.to_string(module)

      #(
        "release",
        dag_json.object([
          #("package", dag_json.string(package)),
          #("version", dag_json.int(version)),
          #("module", dag_json.cid(cid)),
        ]),
      )
    }
  }
}

pub fn fetch_fragment_request(origin, cid) {
  origin.to_request(origin)
  |> request.set_path("/registry/f/" <> cid)
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
    200 -> bit_array.to_string(body)
    _ -> {
      echo response
      todo
    }
  }
}
