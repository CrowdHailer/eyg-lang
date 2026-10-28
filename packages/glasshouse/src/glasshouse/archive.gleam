//// The export format for a session.
////
//// An archive is one JSON document with the session and every stored block it refers to.
//// Anyone with a complete archive can inspect the session and replay its journals.
//// A sandbox attachment additionally holds the sealed input/output environments
//// and ordered external observations. Legacy secret imports may be unstored.

import glasshouse/session.{type Session}
import glasshouse/store.{type Store}
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Archives with a different version are not decoded.
pub const version = 1

pub type Archive {
  Archive(
    session: Session,
    store: Store,
    links: List(Link),
    sandbox: Option(String),
  )
}

/// Where the observability half of a session was uploaded.
pub type Link {
  Langfuse(host: String, trace_id: String)
}

/// An archive with only the blocks the session refers to.
pub fn new(session: Session, store: Store) -> Archive {
  let ids = store.reachable(store, session.references(session))
  Archive(session:, store: store.take(store, ids), links: [], sandbox: None)
}

/// Attach the immutable input/output environments and external observations.
pub fn with_sandbox(archive: Archive, root: String, blocks: Store) -> Archive {
  let blocks = store.merge(archive.store, blocks)
  let ids =
    store.reachable(blocks, [root, ..session.references(archive.session)])
  Archive(..archive, store: store.take(blocks, ids), sandbox: Some(root))
}

pub fn add_link(archive: Archive, link: Link) -> Archive {
  let links = [link, ..list.filter(archive.links, fn(l) { l != link })]
  Archive(..archive, links:)
}

/// Blocks the session refers to that are not in the archive.
pub fn missing(archive: Archive) -> List(String) {
  let Archive(session:, store:, ..) = archive
  let roots = case archive.sandbox {
    None -> session.references(session)
    Some(root) -> [root, ..session.references(session)]
  }
  store.reachable(store, roots)
  |> store.missing(store, _)
}

pub fn encode(archive: Archive) -> json.Json {
  let Archive(session:, store:, links:, sandbox:) = archive
  json.object([
    #("glasshouse", json.int(version)),
    #("session", session.encode(session)),
    #("sandbox", case sandbox {
      None -> json.null()
      Some(root) -> json.string(root)
    }),
    #("links", json.array(links, link_encode)),
    #(
      "blocks",
      store.to_list(store)
        |> list.map(fn(entry) {
          let #(id, block) = entry
          // DAG-JSON blocks are UTF-8 JSON, kept as text so the exact bytes survive.
          let assert Ok(text) = bit_array.to_string(block)
          #(id, json.string(text))
        })
        |> json.object,
    ),
  ])
}

fn link_encode(link) {
  case link {
    Langfuse(host:, trace_id:) ->
      json.object([
        #("type", json.string("langfuse")),
        #("host", json.string(host)),
        #("trace", json.string(trace_id)),
      ])
  }
}

pub fn decoder() -> decode.Decoder(Archive) {
  use version_ <- decode.field("glasshouse", decode.int)
  case version_ == version {
    False ->
      decode.failure(
        Archive(session.Session("", 0, 0, "", None, []), dict.new(), [], None),
        "glasshouse archive version 1",
      )
    True -> {
      use session <- decode.field("session", session.decoder())
      use sandbox <- decode.optional_field(
        "sandbox",
        None,
        decode.optional(decode.string),
      )
      use links <- decode.optional_field(
        "links",
        [],
        decode.list(link_decoder()),
      )
      use blocks <- decode.optional_field(
        "blocks",
        dict.new(),
        decode.dict(decode.string, decode.string),
      )
      let store =
        dict.map_values(blocks, fn(_, text) { bit_array.from_string(text) })
      decode.success(Archive(session:, store:, links:, sandbox:))
    }
  }
}

fn link_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "langfuse" -> {
      use host <- decode.field("host", decode.string)
      use trace_id <- decode.field("trace", decode.string)
      decode.success(Langfuse(host:, trace_id:))
    }
    _ -> decode.failure(Langfuse("", ""), "link")
  }
}

pub fn to_string(archive: Archive) -> String {
  json.to_string(encode(archive))
}

pub fn from_string(text: String) -> Result(Archive, String) {
  json.parse(text, decoder())
  |> result.map_error(fn(error) {
    case error {
      json.UnexpectedEndOfInput -> "the archive is incomplete"
      json.UnexpectedByte(_) | json.UnexpectedSequence(_) ->
        "the archive is not JSON"
      json.UnableToDecode(_) -> "the file is not a glasshouse archive"
    }
  })
}
