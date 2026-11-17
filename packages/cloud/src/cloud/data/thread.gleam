//// A thread is an append only DAG of events.
//// Each event is identified by a key made from its parent's key and its payload,
//// so a key identifies the whole history up to and including the event.
//// Appending an event that is already in the thread changes nothing.

import gleam/crypto
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import multiformats/cid/v1
import multiformats/hashes
import pog

/// `payload` is the event as JSON, it is stored and hashed as it is.
pub type Node {
  Node(key: String, parent: Option(String), payload: String)
}

/// The key of an event appended after `parent`.
pub fn key(parent: Option(String), payload: String) -> String {
  let parent = case parent {
    Some(parent) -> <<1, parent:utf8>>
    None -> <<0>>
  }
  let digest = crypto.hash(crypto.Sha256, <<parent:bits, payload:utf8>>)
  v1.to_string(v1.Cid(0x55, hashes.Multihash(hashes.Sha256, digest)))
}

/// The nodes for events appended in order after `parent`.
pub fn nodes(parent: Option(String), payloads: List(String)) -> List(Node) {
  list.map_fold(payloads, parent, fn(parent, payload) {
    let key = key(parent, payload)
    #(Some(key), Node(key, parent, payload))
  }).1
}

/// Add nodes, those already in the thread are left as they are.
pub fn insert(nodes: List(Node)) -> pog.Query(Nil) {
  "INSERT INTO thread_events (key, parent, payload)
  SELECT key, parent, payload
  FROM unnest($1::TEXT[], $2::TEXT[], $3::TEXT[])
    WITH ORDINALITY AS nodes(key, parent, payload, position)
  ORDER BY position
  ON CONFLICT DO NOTHING"
  |> pog.query()
  |> pog.parameter(pog.array(fn(node: Node) { pog.text(node.key) }, nodes))
  |> pog.parameter(pog.array(
    fn(node: Node) { pog.nullable(pog.text, node.parent) },
    nodes,
  ))
  |> pog.parameter(pog.array(fn(node: Node) { pog.text(node.payload) }, nodes))
}

/// Add nodes with the time each was first recorded, in microseconds since the unix epoch.
pub fn restore(nodes: List(#(Int, Node))) -> pog.Query(Nil) {
  "INSERT INTO thread_events (key, parent, payload, recorded_at)
  SELECT key, parent, payload, to_timestamp(at / 1000000.0)
  FROM unnest($1::TEXT[], $2::TEXT[], $3::TEXT[], $4::BIGINT[])
    WITH ORDINALITY AS nodes(key, parent, payload, at, position)
  ORDER BY position
  ON CONFLICT DO NOTHING"
  |> pog.query()
  |> pog.parameter(pog.array(
    fn(entry: #(Int, Node)) { pog.text({ entry.1 }.key) },
    nodes,
  ))
  |> pog.parameter(pog.array(
    fn(entry: #(Int, Node)) { pog.nullable(pog.text, { entry.1 }.parent) },
    nodes,
  ))
  |> pog.parameter(pog.array(
    fn(entry: #(Int, Node)) { pog.text({ entry.1 }.payload) },
    nodes,
  ))
  |> pog.parameter(pog.array(
    fn(entry: #(Int, Node)) { pog.int(entry.0) },
    nodes,
  ))
}

/// Every event from the start of the thread to `head`, with the time each was recorded in microseconds.
pub fn history(head: String) -> pog.Query(#(Int, Node)) {
  "WITH RECURSIVE path AS (
    SELECT key, parent, payload, recorded_at, 0 AS depth
    FROM thread_events WHERE key = $1
    UNION ALL
    SELECT t.key, t.parent, t.payload, t.recorded_at, path.depth + 1
    FROM thread_events t JOIN path ON t.key = path.parent
  )
  SELECT key, parent, payload, (EXTRACT(EPOCH FROM recorded_at) * 1000000)::BIGINT
  FROM path
  ORDER BY depth DESC"
  |> pog.query()
  |> pog.parameter(pog.text(head))
  |> pog.returning({
    use key <- decode.field(0, decode.string)
    use parent <- decode.field(1, decode.optional(decode.string))
    use payload <- decode.field(2, decode.string)
    use at <- decode.field(3, decode.int)
    decode.success(#(at, Node(key, parent, payload)))
  })
}
