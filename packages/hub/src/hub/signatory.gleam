import dag_json
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import untethered/decoder_set
import untethered/substrate

pub type Entry =
  substrate.Intrinsic(Event)

pub fn first(key) -> Entry {
  let sequence = 1
  let previous = None
  let content = AddKey(key)
  substrate.Entry(sequence:, previous:, signatory: Nil, key:, content:)
}

pub fn encode(entry: Entry) {
  substrate.intrinsic_encode(entry, event_encode)
}

pub fn decoder() {
  substrate.intrinsic_decoder(event_decoder())
}

pub fn to_bytes(entry) {
  substrate.to_bytes(encode(entry))
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
  decoder_set.to_decoder(event_decoders(), _)
}

fn event_decoders() {
  decoder_set.DecoderSet(
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

pub fn state(history) {
  list.fold(history, dict.new(), fn(acc, event) {
    case event {
      AddKey(key) -> dict.insert(acc, key, Nil)
      RemoveKey(key) -> dict.delete(acc, key)
    }
  })
}

pub type Policy {
  AddSelf(key: String)
  Admin
}

pub fn fetch_permissions(key, history) {
  let keys = state(history)
  case history, dict.get(keys, key) {
    [], Error(Nil) -> Ok(AddSelf(key))
    [], Ok(_) -> panic
    // All keys have the same permissions
    _, Ok(Nil) -> Ok(Admin)
    _, Error(Nil) -> Error(Nil)
  }
}
