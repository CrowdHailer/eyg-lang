//// Resolve the types of stable references before storing a module.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/result.{try}
import hub/modules/data
import hub/packages/data as packages
import multiformats/cid/v1
import pog

pub type Unresolved {
  NotShared(cid: v1.Cid)
  NotReadable(cid: v1.Cid)
  NotPinned(reference: ir.Reference)
  UndefinedRelease(release: ir.Release)
  MispinnedRelease(release: ir.Release, published: v1.Cid)
  Invalid(cid: v1.Cid)
}

pub fn describe(reason: Unresolved) -> String {
  case reason {
    NotShared(cid) ->
      "references a module that has not been shared: #" <> v1.to_string(cid)
    NotReadable(cid) ->
      "references a module that cannot be read: #" <> v1.to_string(cid)
    NotPinned(reference) -> not_pinned(reference)
    UndefinedRelease(ir.Release(package, version, _)) ->
      "references an unpublished release: @"
      <> package
      <> ":"
      <> int.to_string(version)
    MispinnedRelease(ir.Release(package, version, module), published) ->
      "release @"
      <> package
      <> ":"
      <> int.to_string(version)
      <> " is pinned to #"
      <> v1.to_string(module)
      <> " but publishes #"
      <> v1.to_string(published)
    Invalid(cid) ->
      "references a module that does not type check: #" <> v1.to_string(cid)
  }
}

fn not_pinned(reference: ir.Reference) -> String {
  case reference {
    ir.Package(package) -> "must pin the version and module of @" <> package
    ir.Version(package, version) ->
      "must pin the module of @" <> package <> ":" <> int.to_string(version)
    ir.Relative(location) ->
      "reaches "
      <> location
      <> ", which names a local file rather than immutable content"
    ir.Content(_) | ir.Pinned(_) -> "reference is not pinned"
  }
}

pub fn resolve(
  source: ir.Node(a),
  db: pog.Connection,
) -> Result(Dict(v1.Cid, binding.Poly), Unresolved) {
  add_all(ir.list_references(source), dict.new(), db)
}

fn add_all(references, types, db) {
  list.try_fold(references, types, fn(types, reference) {
    add_reference(reference, types, db)
  })
}

fn add_reference(reference: ir.Reference, types, db) {
  case reference {
    ir.Content(cid) -> add(cid, types, db)
    ir.Pinned(ir.Release(package, version, module) as release) ->
      case pog.execute(packages.get_release_module(package, version), db) {
        Ok(pog.Returned(rows: [published], ..)) if published == module ->
          add(module, types, db)
        Ok(pog.Returned(rows: [published], ..)) ->
          Error(MispinnedRelease(release:, published:))
        _ -> Error(UndefinedRelease(release))
      }
    ir.Package(_) | ir.Version(_, _) | ir.Relative(_) ->
      Error(NotPinned(reference))
  }
}

fn add(cid, types, db) {
  case dict.has_key(types, cid) {
    True -> Ok(types)
    False -> {
      use source <- try(read(cid, db))
      use types <- try(add_all(ir.list_references(source), types, db))
      let analysis =
        infer.pure()
        |> infer.with_references(types)
        |> infer.check(source)
      case infer.all_errors(analysis) {
        [] -> Ok(dict.insert(types, cid, infer.poly_type(analysis)))
        _ -> Error(Invalid(cid))
      }
    }
  }
}

fn read(cid, db) {
  case pog.execute(data.get(v1.to_string(cid)), db) {
    Ok(pog.Returned(rows: [module], ..)) ->
      json.parse(module.source, dag_json.decoder(Nil))
      |> result.replace_error(NotReadable(cid))
    _ -> Error(NotShared(cid))
  }
}
