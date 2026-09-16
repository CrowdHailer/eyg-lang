//// The context a the module that is in scope for an overlay session run.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug as analysis_debug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value
import eyg/ir/tree as ir
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri
import multiformats/cid/v1
import overlay/web/tools

pub const default_readme = "This is the overlay agent"

pub fn default() -> cache.Module(_) {
  cache.Module(
    value: value.Record(
      dict.from_list([#("readme", value.String(default_readme))]),
    ),
    type_: t.record([#("readme", t.String)]),
  )
}

pub type Source {
  Default
  Reference(cid: v1.Cid)
  Package(name: String, version: Option(Int))
  Invalid(raw: String, reason: String)
}

/// Parse the search component of the page location, with or without its "?".
pub fn from_search(search: String) -> Source {
  let query = case search {
    "?" <> query -> query
    query -> query
  }
  case uri.parse_query(query) {
    Ok(query) -> from_query(query)
    Error(Nil) ->
      Invalid(
        raw: "?" <> query,
        reason: "The context query could not be parsed.",
      )
  }
}

/// - `?reference=<cid>` selects a module by content.
/// - `?package=<name>` selects the latest release of a package.
/// - `?package=<name>&version=<n>` selects a single release.
pub fn from_query(query: List(#(String, String))) -> Source {
  case
    list.key_find(query, "reference"),
    list.key_find(query, "package"),
    list.key_find(query, "version")
  {
    Ok(reference), Ok(name), _ ->
      Invalid(
        raw: "?reference=" <> reference <> "&package=" <> name,
        reason: "Set only one of the reference and package parameters.",
      )
    Ok(reference), Error(Nil), Ok(version) ->
      Invalid(
        raw: "?reference=" <> reference <> "&version=" <> version,
        reason: "The version parameter requires a package.",
      )
    Ok(reference), Error(Nil), Error(Nil) -> parse_reference(reference)
    Error(Nil), Ok(name), version -> parse_package(name, version)
    Error(Nil), Error(Nil), Ok(version) ->
      Invalid(
        raw: "?version=" <> version,
        reason: "The version parameter requires a package.",
      )
    Error(Nil), Error(Nil), Error(Nil) -> Default
  }
}

fn parse_reference(reference) {
  case v1.from_string(reference) {
    Ok(#(cid, <<>>)) -> Reference(cid)
    _ ->
      Invalid(
        raw: "#" <> reference,
        reason: "Not a valid reference: " <> reference,
      )
  }
}

fn parse_package(name, version) {
  case version {
    Error(Nil) -> Package(name:, version: None)
    Ok(raw) ->
      case int.parse(raw) {
        Ok(version) if version > 0 -> Package(name:, version: Some(version))
        Ok(_) ->
          Invalid(
            raw: "@" <> name <> ":" <> raw,
            reason: "Version must be greater than zero: " <> raw,
          )
        Error(Nil) ->
          Invalid(
            raw: "@" <> name <> ":" <> raw,
            reason: "Not a valid version: " <> raw,
          )
      }
  }
}

/// A short name for the requested context, to show to the user.
pub fn describe(source: Source) -> String {
  case source {
    Default -> "overlay"
    Reference(cid:) -> "#" <> v1.to_string(cid)
    Package(name:, version: None) -> "@" <> name
    Package(name:, version: Some(version)) ->
      "@" <> name <> ":" <> int.to_string(version)
    Invalid(raw:, reason: _) -> raw
  }
}

pub type Status {
  Pulling(reference: ir.Reference)
  Fetching(cids: List(v1.Cid), reference: ir.Reference)
  Errored(reason: String)
  Loaded(module: cache.Module(tools.Meta))
}

pub fn load(source, cache) {
  case source {
    Default -> #(Loaded(default()), cache)
    Reference(cid:) -> {
      let cache = cache.fetch(cache, cid)
      #(Fetching([cid], ir.Content(cid)), cache)
    }
    Package(name:, version:) -> {
      let cache = cache.pull(cache)
      let reference = case version {
        Some(version) -> ir.Version(name, version)
        None -> ir.Package(name)
      }
      #(Pulling(reference), cache)
    }
    Invalid(raw: _, reason:) -> #(Errored(reason), cache)
  }
}

pub fn pulled(status, cache) {
  case status {
    Pulling(reference) -> {
      let source = #(ir.Reference(reference), [])
      let analysis = check(source, cache)
      case infer.all_errors(analysis) {
        [] -> #(loaded(source, analysis, cache), cache)
        errors ->
          case tools.to_fetch(tools.missing_references(errors), cache, []) {
            // The release log is up to date, so a reference that is still
            // missing is one the hub does not have.
            [] -> #(Errored(describe_errors(errors)), cache)
            missing -> #(
              Fetching(missing, reference:),
              cache.fetch_all(cache, missing),
            )
          }
      }
    }
    Fetching(..) | Errored(..) | Loaded(..) -> #(status, cache)
  }
}

pub fn check_fetching(status, cache) {
  case status {
    Fetching(cids, reference) ->
      case list.filter(cids, tools.still_fetching(_, cache)) {
        [] -> {
          let source = #(ir.Reference(reference), [])
          let analysis = check(source, cache)
          case infer.all_errors(analysis) {
            [] -> loaded(source, analysis, cache)
            // The cache follows the dependencies of a module it fetches, so
            // nothing further arrives to resolve these.
            errors -> Errored(describe_errors(errors))
          }
        }
        // Because we check pulled status and then fetching this branch is reached almost immediatly
        _remaining -> status
      }
    Pulling(..) | Errored(..) | Loaded(..) -> status
  }
}

fn check(source, cache) {
  infer.pure()
  |> infer.check(source)
  |> cache.infer_sync(cache)
}

fn loaded(source, analysis, cache) -> Status {
  let return =
    expression.execute(source, [])
    |> cache.static_loop(cache, expression.resume)
  case return {
    Ok(value) -> Loaded(cache.Module(value:, type_: infer.poly_type(analysis)))
    // The module type checked, so it is only ever the module aborting as it
    // is built that gets here.
    Error(#(reason, _meta, _env, _k)) -> Errored(simple_debug.describe(reason))
  }
}

fn describe_errors(errors: List(#(a, error.Reason))) {
  list.map(errors, fn(error) { analysis_debug.reason(error.1) })
  |> string.join("\n")
}

/// True while the requested context is still being looked up.
pub fn loading(status: Status) -> Bool {
  case status {
    Pulling(..) | Fetching(..) -> True
    Errored(..) | Loaded(..) -> False
  }
}

/// The module in scope for every program the agent runs.
pub fn module(status: Status) -> cache.Module(tools.Meta) {
  case status {
    Loaded(module:) -> module
    Pulling(..) | Fetching(..) | Errored(..) -> default()
  }
}

/// The module's own instructions, if it has a string readme field.
pub fn provided_readme(status: Status) -> Option(String) {
  let cache.Module(value: module, ..) = module(status)
  case module {
    value.Record(fields) ->
      case dict.get(fields, "readme") {
        Ok(value.String(readme)) -> Some(readme)
        _ -> None
      }
    _ -> None
  }
}

/// The instructions the agent is given for this session.
pub fn readme(status: Status) -> String {
  case provided_readme(status) {
    Some(readme) -> readme
    None -> {
      let cache.Module(type_:, ..) = module(status)
      let #(type_, _) = binding.instantiate(type_, 0, dict.new())
      default_readme
      <> "\n\nThe context module has type:\n"
      <> analysis_debug.mono(type_)
    }
  }
}
