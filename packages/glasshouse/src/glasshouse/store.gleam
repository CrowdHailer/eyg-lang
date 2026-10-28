//// A content addressed store of EYG modules.
////
//// Every block is a DAG-JSON encoded EYG expression identified by its CID.
//// Code, recorded values and file contents are all modules,
//// the contents of a file are stored as a `Binary` module.

import dag_json
import eyg/ir/dag_json as ir_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import multiformats/cid/v1
import multiformats/hashes

/// Blocks keyed by the string form of their CID.
pub type Store =
  Dict(String, BitArray)

/// SHA-256 is the only hash a store uses.
/// It is passed in so the store is independent of any runtime.
pub type Sha256 =
  fn(BitArray) -> BitArray

pub fn new() -> Store {
  dict.new()
}

/// The CID of a DAG-JSON block.
pub fn cid(block: BitArray, sha256: Sha256) -> v1.Cid {
  v1.Cid(dag_json.code(), hashes.Multihash(hashes.Sha256, sha256(block)))
}

/// Add a block, returning the string form of its CID.
pub fn put(store: Store, block: BitArray, sha256: Sha256) -> #(Store, String) {
  let id = v1.to_string(cid(block, sha256))
  #(dict.insert(store, id, block), id)
}

/// Add an expression as a module.
pub fn put_node(
  store: Store,
  node: ir.Node(a),
  sha256: Sha256,
) -> #(Store, String) {
  put(store, ir_json.to_block(node), sha256)
}

/// Add bytes as a `Binary` module.
pub fn put_binary(
  store: Store,
  bytes: BitArray,
  sha256: Sha256,
) -> #(Store, String) {
  put_node(store, #(ir.Binary(bytes), Nil), sha256)
}

pub fn get(store: Store, id: String) -> Result(BitArray, Nil) {
  dict.get(store, id)
}

pub fn has(store: Store, id: String) -> Bool {
  dict.has_key(store, id)
}

/// Decode the module stored for a CID.
pub fn get_node(store: Store, id: String) -> Result(ir.Node(Nil), String) {
  case dict.get(store, id) {
    Ok(block) ->
      json.parse_bits(block, ir_json.decoder(Nil))
      |> result.replace_error("invalid module in store " <> id)
    Error(Nil) -> Error("missing module in store " <> id)
  }
}

/// The bytes of a stored `Binary` module.
pub fn get_binary(store: Store, id: String) -> Result(BitArray, String) {
  use node <- result.try(get_node(store, id))
  case node {
    #(ir.Binary(bytes), _) -> Ok(bytes)
    _ -> Error("module is not a binary " <> id)
  }
}

pub fn merge(store: Store, other: Store) -> Store {
  dict.merge(store, other)
}

pub fn from_list(blocks: List(#(String, BitArray))) -> Store {
  dict.from_list(blocks)
}

/// All blocks ordered by CID.
pub fn to_list(store: Store) -> List(#(String, BitArray)) {
  dict.to_list(store)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// Keep only the blocks with the given CIDs.
pub fn take(store: Store, ids: List(String)) -> Store {
  dict.take(store, ids)
}

/// The given CIDs and every module they refer to, transitively.
/// CIDs not in the store are included so missing blocks can be reported.
pub fn reachable(store: Store, roots: List(String)) -> List(String) {
  do_reachable(store, roots, set.new())
  |> set.to_list
  |> list.sort(string.compare)
}

fn do_reachable(store, pending, seen) {
  case pending {
    [] -> seen
    [id, ..rest] ->
      case set.contains(seen, id) {
        True -> do_reachable(store, rest, seen)
        False -> {
          let seen = set.insert(seen, id)
          let children = case get_node(store, id) {
            Ok(node) ->
              ir.list_references(node)
              |> list.filter_map(fn(reference) {
                case reference {
                  ir.Content(cid) -> Ok(v1.to_string(cid))
                  ir.Pinned(ir.Release(module:, ..)) -> Ok(v1.to_string(module))
                  _ -> Error(Nil)
                }
              })
            Error(_) -> []
          }
          do_reachable(store, list.append(children, rest), seen)
        }
      }
  }
}

/// CIDs that are not in the store.
pub fn missing(store: Store, ids: List(String)) -> List(String) {
  list.filter(ids, fn(id) { !dict.has_key(store, id) })
}

/// Blocks that do not hash to the CID they are stored under.
pub fn corrupt(store: Store, sha256: Sha256) -> List(String) {
  dict.to_list(store)
  |> list.filter_map(fn(entry) {
    let #(id, block) = entry
    case v1.to_string(cid(block, sha256)) == id {
      True -> Error(Nil)
      False -> Ok(id)
    }
  })
  |> list.sort(string.compare)
}
