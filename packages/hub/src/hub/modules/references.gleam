//// The types of the modules a module reaches, so a shared module can be
//// checked against them.
////
//// A module is checked before it is stored, and a module that uses a package
//// only checks against the type that package actually has. The hub holds
//// every module it has been sent, so the types are read from its own store
//// rather than fetched.
////
//// A reference must be pinned. A content identifier promises that the same id
//// is always the same program, and `@standard` with no version breaks that
//// promise the next time standard is released. So the hub takes
//// `@standard:1:baguqee…` and refuses `@standard`.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/result.{try}
import hub/modules/data
import multiformats/cid/v1
import pog

pub type Unresolved {
  /// A module that references another the hub has never been sent.
  NotShared(cid: v1.Cid)
  /// A module whose source is in the store but is not readable as EYG.
  NotReadable(cid: v1.Cid)
  /// `@standard` rather than `@standard:1:baguqee…`.
  NotPinned(package: String)
}

pub fn describe(reason: Unresolved) -> String {
  case reason {
    NotShared(cid:) ->
      "references a module that has not been shared: #" <> v1.to_string(cid)
    NotReadable(cid:) ->
      "references a module that cannot be read: #" <> v1.to_string(cid)
    NotPinned(package:) ->
      "must pin the version and hash of @"
      <> package
      <> ", an unpinned package would change what this module means"
  }
}

/// The type of every module this source references, keyed by content id.
///
/// Every module a reference reaches is resolved, so a module two steps away
/// is checked as well.
pub fn resolve(
  source: ir.Node(a),
  db: pog.Connection,
) -> Result(Dict(v1.Cid, binding.Poly), Unresolved) {
  use Nil <- try(all_pinned(source))
  use types <- try(add_all(ir.list_references(source), dict.new(), db))
  Ok(types)
}

/// A published module is read by its content id long after it was written, so
/// the packages it uses have to be the ones it was written against.
fn all_pinned(source: ir.Node(a)) -> Result(Nil, Unresolved) {
  ir.list_named_references(source)
  |> list.try_fold(Nil, fn(_, reference) {
    let #(package, version, module) = reference
    case version, module == dag_json.vacant_cid {
      0, _ | _, True -> Error(NotPinned(package))
      _, False -> Ok(Nil)
    }
  })
}

fn add_all(
  cids: List(v1.Cid),
  types: Dict(v1.Cid, binding.Poly),
  db: pog.Connection,
) -> Result(Dict(v1.Cid, binding.Poly), Unresolved) {
  list.try_fold(cids, types, fn(types, cid) { add(cid, types, db) })
}

fn add(
  cid: v1.Cid,
  types: Dict(v1.Cid, binding.Poly),
  db: pog.Connection,
) -> Result(Dict(v1.Cid, binding.Poly), Unresolved) {
  case dict.has_key(types, cid) {
    True -> Ok(types)
    False -> {
      use source <- try(read(cid, db))
      // A module already in the store was checked when it was shared, its own
      // references are followed only to give it a type here.
      use types <- try(add_all(ir.list_references(source), types, db))
      let type_ =
        infer.pure()
        |> infer.with_references(types)
        |> infer.check(source)
        |> infer.poly_type
      Ok(dict.insert(types, cid, type_))
    }
  }
}

fn read(cid: v1.Cid, db: pog.Connection) -> Result(ir.Node(Nil), Unresolved) {
  case pog.execute(data.get(v1.to_string(cid)), db) {
    Ok(pog.Returned(rows: [module], ..)) ->
      json.parse(module.source, dag_json.decoder(Nil))
      |> result.replace_error(NotReadable(cid))
    _ -> Error(NotShared(cid))
  }
}
