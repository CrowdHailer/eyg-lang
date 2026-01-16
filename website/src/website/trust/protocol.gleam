import dag_json
import gleam/dynamic/decode
import website/trust/substrate

pub fn encode(entry: substrate.Entry(Event)) {
  substrate.entry_encode(entry, event_encode)
}

pub fn decoder() {
  substrate.entry_decoder(event_decoders())
}

pub type Event {
  AddKey(String)
}

pub fn event_encode(event: Event) {
  case event {
    AddKey(key) -> #(
      "add_key",
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
    ],
    AddKey(""),
  )
}
