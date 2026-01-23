import gleam/dynamic/decode
import gleam/json
import trust/substrate
import website/registry/protocol

pub type OpenerBound {
  GetPayload
}

pub fn opener_bound_encode(message) {
  json.object([
    #("type", json.string("get_payload")),
    #("exchange", json.string("123")),
  ])
}

pub type PopupBound {
  Payload(payload: substrate.Entry(protocol.Payload))
}

pub fn popup_bound_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "payload" -> {
      use payload <- decode.field("payload", protocol.decoder())
      decode.success(Payload(payload:))
    }
    _ -> todo
  }
}
