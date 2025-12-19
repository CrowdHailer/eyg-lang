import dag_json
import gleam/dynamic/decode
import multiformats/cid/v1

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
