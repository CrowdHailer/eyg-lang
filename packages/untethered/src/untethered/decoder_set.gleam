import gleam/dynamic/decode.{type Decoder}
import gleam/list

pub type DecoderSet(t) {
  DecoderSet(decoders: List(#(String, Decoder(t))), zero: t)
}

pub fn to_decoder(set, type_) {
  let DecoderSet(decoders:, zero:) = set
  case list.key_find(decoders, type_) {
    Ok(decoder) -> decoder
    Error(Nil) -> decode.failure(zero, "unknown type")
  }
}
