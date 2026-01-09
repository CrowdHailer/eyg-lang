import gleam/dynamic/decode
import gleam/json

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
  Payload(payload: String)
}

pub fn popup_bound_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "payload" -> {
      use payload <- decode.field("payload", decode.string)
      decode.success(Payload(payload:))
    }
    _ -> todo
  }
}
