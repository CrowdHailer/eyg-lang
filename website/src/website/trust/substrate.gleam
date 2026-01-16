import dag_json
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import multiformats/cid/v1

pub type Entry(t) {
  Entry(
    entity: String,
    sequence: Int,
    previous: Option(v1.Cid),
    signatory: Signatory,
    content: t,
  )
}

pub fn entry_decoder(
  content_decoders: List(#(String, decode.Decoder(t))),
) -> decode.Decoder(Entry(t)) {
  // content_decoders List(String -> decoder)
  use entity <- decode.field("entity", decode.string)
  use sequence <- decode.field("sequence", decode.int)
  use previous <- decode.field(
    "previous",
    decode.optional(dag_json.decode_cid()),
  )
  use signatory <- decode.field("signatory", signatory_decoder())
  use type_ <- decode.field("type", decode.string)
  use content <- decode.then(case list.key_find(content_decoders, type_) {
    Ok(decoder) -> decode.field("content", decoder, decode.success)
    Error(Nil) -> {
      echo type_
      todo
    }
  })
  decode.success(Entry(entity:, sequence:, previous:, signatory:, content:))
}

pub fn entry_encode(entry: Entry(t), content_encode) {
  let #(type_, content) = content_encode(entry.content)
  dag_json.object([
    #("entity", dag_json.string(entry.entity)),
    #("sequence", dag_json.int(entry.sequence)),
    #(
      "previous",
      dag_json.nullable(entry.previous, fn(cid) {
        let assert Ok(cid) = v1.to_string(cid)
        dag_json.cid(cid)
      }),
    ),
    #("signatory", signatory_encode(entry.signatory)),
    #("type", dag_json.string(type_)),
    #("content", content),
  ])
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
