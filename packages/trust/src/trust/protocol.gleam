import dag_json
import gleam/dynamic/decode
import gleam/json
import trust/substrate

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
