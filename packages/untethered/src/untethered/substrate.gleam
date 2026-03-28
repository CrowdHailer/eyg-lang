import dag_json
import gleam/bit_array
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/option.{type Option}
import multiformats/cid/v1

pub type Entry(sig, content) {
  Entry(
    sequence: Int,
    previous: Option(v1.Cid),
    signatory: sig,
    key: String,
    content: content,
  )
}

pub type Intrinsic(t) =
  Entry(Nil, t)

pub type Delegated(t) =
  Entry(v1.Cid, t)

pub fn intrinsic_decoder(
  content_decoder: fn(String) -> Decoder(t),
) -> Decoder(Intrinsic(t)) {
  use sequence <- decode.field("sequence", decode.int)
  use previous <- decode.field(
    "previous",
    decode.optional(dag_json.decode_cid()),
  )
  let signatory = Nil
  use key <- decode.field("key", decode.string)
  use type_ <- decode.field("type", decode.string)
  use content <- decode.field("content", content_decoder(type_))
  decode.success(Entry(sequence:, previous:, signatory:, key:, content:))
}

pub fn intrinsic_encode(entry: Intrinsic(t), content_encode) {
  let #(type_, content) = content_encode(entry.content)
  dag_json.object([
    #("sequence", dag_json.int(entry.sequence)),
    #("previous", dag_json.nullable(entry.previous, dag_json.cid)),
    #("key", dag_json.string(entry.key)),
    #("type", dag_json.string(type_)),
    #("content", content),
  ])
}

pub fn delegated_decoder(
  content_decoder: fn(String) -> Decoder(t),
) -> Decoder(Delegated(t)) {
  use sequence <- decode.field("sequence", decode.int)
  use previous <- decode.field(
    "previous",
    decode.optional(dag_json.decode_cid()),
  )
  use signatory <- decode.field("signatory", dag_json.decode_cid())
  use key <- decode.field("key", decode.string)
  use type_ <- decode.field("type", decode.string)
  use content <- decode.field("content", content_decoder(type_))

  decode.success(Entry(sequence:, previous:, signatory:, key:, content:))
}

pub fn delegated_encode(entry: Delegated(t), content_encode) {
  let #(type_, content) = content_encode(entry.content)
  dag_json.object([
    #("sequence", dag_json.int(entry.sequence)),
    #("previous", dag_json.nullable(entry.previous, dag_json.cid)),
    #("signatory", dag_json.cid(entry.signatory)),
    #("key", dag_json.string(entry.key)),
    #("type", dag_json.string(type_)),
    #("content", content),
  ])
}

// To make the gleam_ir library portable over browser, node and erlang you need to bring your own sha implementation
// pub type Effect(t) {
//   Sha256(bytes: BitArray, resume: fn(BitArray) -> t)
// }

// pub fn cid_from_entry(entry, encode) {
//   let bytes =
//     entry_encode(entry, encode) |> json.to_string |> bit_array.from_string
//   from_block(bytes)
// }

pub fn to_bytes(data) {
  data |> json.to_string |> bit_array.from_string
}
// fn from_block(bytes) {
//   Sha256(bytes:, resume: fn(digest) {
//     let multihash = hashes.Multihash(hashes.Sha256, digest)
//     v1.Cid(dag_json.code(), multihash)
//   })
// }
