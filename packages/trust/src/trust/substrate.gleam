import dag_json
import gleam/bit_array
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import multiformats/cid/v1
import multiformats/hashes

pub type Entry(t) {
  Entry(
    sequence: Int,
    previous: Option(v1.Cid),
    signatory: v1.Cid,
    key: String,
    content: t,
  )
}

pub type DecoderSet(t) {
  DecoderSet(decoders: List(#(String, Decoder(t))), zero: t)
}

pub fn decode_set(set, type_) {
  let DecoderSet(decoders:, zero:) = set
  case list.key_find(decoders, type_) {
    Ok(decoder) -> decoder
    Error(Nil) -> decode.failure(zero, "known type")
  }
}

pub fn entry_decoder(inner: fn(String) -> Decoder(t)) -> Decoder(Entry(t)) {
  use sequence <- decode.field("sequence", decode.int)
  use previous <- decode.field(
    "previous",
    decode.optional(dag_json.decode_cid()),
  )
  use signatory <- decode.field("signatory", dag_json.decode_cid())
  use key <- decode.field("key", decode.string)
  use type_ <- decode.field("type", decode.string)
  use content <- decode.field("content", inner(type_))

  decode.success(Entry(sequence:, previous:, signatory:, key:, content:))
}

pub fn entry_encode(entry: Entry(t), content_encode) {
  let #(type_, content) = content_encode(entry.content)
  dag_json.object([
    #("sequence", dag_json.int(entry.sequence)),
    #("previous", dag_json.nullable(entry.previous, cid_encode)),
    #("signatory", cid_encode(entry.signatory)),
    #("key", dag_json.string(entry.key)),
    #("type", dag_json.string(type_)),
    #("content", content),
  ])
}

fn cid_encode(cid) {
  let assert Ok(cid) = v1.to_string(cid)
  dag_json.cid(cid)
}

/// To make the gleam_ir library portable over browser, node and erlang you need to bring your own sha implementation
pub type Effect(t) {
  Sha256(bytes: BitArray, resume: fn(BitArray) -> t)
}

pub fn cid_from_entry(entry, encode) {
  let bytes =
    entry_encode(entry, encode) |> json.to_string |> bit_array.from_string
  from_block(bytes)
}

fn from_block(bytes) {
  Sha256(bytes:, resume: fn(digest) {
    let multihash = hashes.Multihash(hashes.Sha256, digest)
    v1.Cid(dag_json.code(), multihash)
  })
}

pub type Signatory {
  Signatory(entity: String, sequence: Int, key: String)
}

fn signatory_decoder() {
  use entity <- decode.field("entity", decode.string)
  use sequence <- decode.field("sequence", decode.int)
  use key <- decode.field("key", decode.string)
  decode.success(Signatory(entity, sequence, key))
}

fn signatory_encode(signatory) {
  let Signatory(entity, sequence, key) = signatory
  dag_json.object([
    #("entity", dag_json.string(entity)),
    #("sequence", dag_json.int(sequence)),
    #("key", dag_json.string(key)),
  ])
}
