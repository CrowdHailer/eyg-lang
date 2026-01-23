import dag_json
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}
import multiformats/cid/v1
import multiformats/hashes
import trust/substrate.{Entry}

pub fn first(key) {
  let sequence = 1
  let previous = None
  let content = AddKey(key)
  Entry(
    sequence:,
    previous:,
    signatory: v1.Cid(dag_json.code(), hashes.Multihash(hashes.Sha256, <<>>)),
    key:,
    content:,
  )
}

pub fn encode(entry: substrate.Entry(Event)) {
  substrate.entry_encode(entry, event_encode)
}

pub fn decoder() {
  substrate.entry_decoder(substrate.decode_set(event_decoders(), _))
}

pub type Event {
  AddKey(String)
  RemoveKey(String)
}

pub fn event_encode(event: Event) {
  case event {
    AddKey(key) -> #(
      "add_key",
      dag_json.object([#("key", dag_json.string(key))]),
    )
    RemoveKey(key) -> #(
      "remove_key",
      dag_json.object([#("key", dag_json.string(key))]),
    )
  }
}

pub fn event_decoder() {
  substrate.decode_set(event_decoders(), _)
}

fn event_decoders() {
  substrate.DecoderSet(
    [
      #("add_key", {
        use key <- decode.field("key", decode.string)
        decode.success(AddKey(key))
      }),
      #("remove_key", {
        use key <- decode.field("key", decode.string)
        decode.success(RemoveKey(key))
      }),
    ],
    AddKey(""),
  )
}

pub type PullEventsResponse {
  PullEventsResponse(events: List(substrate.Entry(Event)), cursor: Int)
}

pub fn pull_events_response_decoder() {
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
