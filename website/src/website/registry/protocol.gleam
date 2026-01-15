import dag_json
import multiformats/cid/v1

pub type Event {
  Release(version: Int, module: v1.Cid)
}

pub const release = "release"

pub fn event_decoders() {
  [release, { todo }]
}

pub fn event_encode(event) {
  case event {
    Release(version:, module:) ->
      dag_json.object([
        #("version", dag_json.int(version)),
        #("module", {
          let assert Ok(cid) = v1.to_string(module)
          dag_json.cid(cid)
        }),
      ])
  }
}
