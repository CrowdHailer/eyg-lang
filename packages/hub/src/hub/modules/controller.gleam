import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/hub/schema
import eyg/ir/car
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dict
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import hub/cid
import hub/modules/bundle
import hub/modules/data
import hub/packages/data as packages
import hub/server/context.{type Context}
import hub/web/utils
import multiformats/cid/v1
import pog
import wisp

pub fn share(
  request: Request(wisp.Connection),
  context: Context,
) -> Response(wisp.Body) {
  case is_archive(request) {
    True -> share_archive(request, context)
    False -> share_module(request, context)
  }
}

fn is_archive(request: Request(wisp.Connection)) -> Bool {
  case request.get_header(request, "content-type") {
    Ok(value) ->
      case string.split(value, ";") {
        [media_type, ..] ->
          media_type |> string.trim |> string.lowercase == car.content_type
        [] -> False
      }
    Error(Nil) -> False
  }
}

fn share_module(
  request: Request(wisp.Connection),
  context: Context,
) -> Response(wisp.Body) {
  use <- wisp.require_content_type(request, "application/json")
  let request = wisp.set_max_body_size(request, 50_000)
  use source_text <- wisp.require_string_body(request)
  use <- check_size(string.byte_size(source_text), 50_000)
  use source <- utils.do_decode(source_text, dag_json.decoder(Nil))
  let root = cid.from_tree(source)
  accept(
    bundle.Bundle(root: #(root, source), dependencies: []),
    context,
    uploaded_by(request),
  )
}

fn share_archive(
  request: Request(wisp.Connection),
  context: Context,
) -> Response(wisp.Body) {
  let request = wisp.set_max_body_size(request, 500_000)
  use body <- wisp.require_bit_array_body(request)
  use <- check_size(bit_array.byte_size(body), 500_000)
  case bundle.shake(body) {
    Ok(archive) -> accept(archive, context, uploaded_by(request))
    Error(reason) -> utils.api_reason(422, describe_shake_error(reason))
  }
}

fn describe_shake_error(reason) {
  case reason {
    bundle.InvalidCar(reason) -> reason
    bundle.UnsupportedVersion(_) -> "unsupported CAR version"
    bundle.InvalidRootCount(_) -> "an archive must have exactly one root"
    bundle.IncorrectCid(declared:, actual:) ->
      v1.to_string(declared)
      <> " does not identify its canonical module; expected "
      <> v1.to_string(actual)
    bundle.DuplicateCid(cid) ->
      "archive contains duplicate block " <> v1.to_string(cid)
    bundle.InvalidModule(cid) -> v1.to_string(cid) <> " is not a module"
    bundle.MissingRoot(cid) ->
      "archive does not contain its root " <> v1.to_string(cid)
    bundle.Circular(cycle) ->
      "bundle contains a circular dependency: "
      <> string.join(list.map(cycle, v1.to_string), " -> ")
  }
}

fn accept(
  archive: bundle.Bundle(Nil),
  context: Context,
  ip: String,
) -> Response(wisp.Body) {
  case bundle.check(archive, infer.pure(), stored(context, [])) {
    Error(bundle.ResolutionFailed(reason)) -> {
      wisp.log_warning(reason)
      wisp.internal_server_error()
    }
    Error(rejection) -> utils.api_reason(422, describe(rejection))
    Ok(_) -> write(archive, context, ip)
  }
}

fn write(
  archive: bundle.Bundle(Nil),
  context: Context,
  ip: String,
) -> Response(wisp.Body) {
  let bundle.Bundle(root: #(root, _), ..) = archive
  let written =
    pog.execute(data.insert_bundle(bundle.blocks(archive), ip), context.db)
  case written {
    Ok(_) ->
      wisp.ok()
      |> wisp.json_body(json.to_string(schema.share_response_encode(root)))
    Error(reason) -> {
      wisp.log_warning(string.inspect(reason))
      wisp.internal_server_error()
    }
  }
}

fn uploaded_by(request: Request(wisp.Connection)) -> String {
  case request.get_header(request, "x-forwarded-for") {
    Ok(value) ->
      value
      |> string.split(",")
      |> list.last
      |> result.map(string.trim)
      |> result.unwrap("0.0.0.0")
    Error(Nil) -> "0.0.0.0"
  }
}

fn describe(rejection: bundle.Rejection(Nil, String)) -> String {
  case rejection {
    bundle.Unsound(module:, ..) ->
      v1.to_string(module) <> " is not a sound and pure module"
    bundle.Missing(module:, reference:) ->
      case reference {
        ir.Package(..) | ir.Version(..) | ir.Relative(..) ->
          v1.to_string(module)
          <> " references "
          <> render_reference(reference)
          <> ", which does not name a shareable module"
        _ ->
          v1.to_string(module)
          <> " references "
          <> render_reference(reference)
          <> ", which is neither in the archive nor already stored"
      }
    bundle.ResolutionFailed(_) -> "dependency resolution failed"
  }
}

fn render_reference(reference: ir.Reference) -> String {
  case reference {
    ir.Content(cid:) -> "#" <> v1.to_string(cid)
    ir.Package(package:) -> "@" <> package
    ir.Version(package:, version:) ->
      "@" <> package <> ":" <> int.to_string(version)
    ir.Pinned(ir.Release(package:, version:, module:)) ->
      "@"
      <> package
      <> ":"
      <> int.to_string(version)
      <> ":"
      <> v1.to_string(module)
    ir.Relative(location:) -> "\"" <> location <> "\""
  }
}

fn check_size(size: Int, max, then) {
  case size <= max {
    True -> then()
    False -> wisp.content_too_large()
  }
}

fn stored(context: Context, visiting) {
  fn(reference) { resolve_stored(reference, context, visiting) }
}

fn resolve_stored(reference, context, visiting) {
  case reference {
    ir.Content(cid:) -> type_of(cid, context, visiting)
    ir.Pinned(ir.Release(package:, version:, module:)) ->
      resolve_release(package, version, module, context, visiting)
    _ -> Error(bundle.NotFound)
  }
}

fn resolve_release(
  package: String,
  version: Int,
  module: v1.Cid,
  context: Context,
  visiting: List(v1.Cid),
) {
  case pog.execute(packages.get_release(package, version), context.db) {
    Ok(pog.Returned(rows: [release], ..)) ->
      case release.module == v1.to_string(module) {
        True -> type_of(module, context, visiting)
        False -> Error(bundle.NotFound)
      }
    Ok(pog.Returned(rows: [], ..)) -> Error(bundle.NotFound)
    Ok(_) ->
      Error(bundle.Failed(
        "release lookup returned an unexpected number of rows",
      ))
    Error(reason) -> Error(bundle.Failed(string.inspect(reason)))
  }
}

fn type_of(
  module: v1.Cid,
  context: Context,
  visiting: List(v1.Cid),
) -> Result(binding.Poly, bundle.ResolveError(String)) {
  use Nil <- result.try(case list.contains(visiting, module) {
    True ->
      Error(bundle.Failed(
        "stored modules contain a dependency cycle through "
        <> v1.to_string(module),
      ))
    False -> Ok(Nil)
  })
  use source <- result.try(
    case pog.execute(data.get(v1.to_string(module)), context.db) {
      Ok(pog.Returned(rows: [held], ..)) ->
        json.parse(held.source, dag_json.decoder(Nil))
        |> result.map_error(fn(reason) {
          bundle.Failed(
            "stored module "
            <> v1.to_string(module)
            <> " is invalid: "
            <> string.inspect(reason),
          )
        })
      Ok(pog.Returned(rows: [], ..)) -> Error(bundle.NotFound)
      Ok(_) ->
        Error(bundle.Failed(
          "stored module lookup returned an unexpected number of rows",
        ))
      Error(reason) -> Error(bundle.Failed(string.inspect(reason)))
    },
  )
  use Nil <- result.try(case cid.from_tree(source) == module {
    True -> Ok(Nil)
    False ->
      Error(bundle.Failed(
        "stored module "
        <> v1.to_string(module)
        <> " does not match its content ID",
      ))
  })
  let archive = bundle.Bundle(root: #(module, source), dependencies: [])
  case
    bundle.check(archive, infer.pure(), stored(context, [module, ..visiting]))
  {
    Ok(bundle.Checked(types:, ..)) ->
      dict.get(types, module)
      |> result.map_error(fn(_) {
        bundle.Failed("stored module was checked without producing a type")
      })
    Error(bundle.ResolutionFailed(reason)) -> Error(bundle.Failed(reason))
    Error(_) ->
      Error(bundle.Failed(
        "stored module " <> v1.to_string(module) <> " is not shareable",
      ))
  }
}

pub fn get(cid: String, context: Context) -> Response(wisp.Body) {
  use cid <- decode_cid(cid)
  case pog.execute(data.get(v1.to_string(cid)), context.db) {
    Ok(pog.Returned(rows: [module], ..)) ->
      wisp.ok()
      |> wisp.json_body(module.source)
    Ok(pog.Returned(rows: [], ..)) -> wisp.no_content()
    Ok(_) -> wisp.internal_server_error()
    Error(_reason) -> wisp.internal_server_error()
  }
}

fn decode_cid(cid, then) {
  case v1.from_string(cid) {
    Ok(#(cid, <<>>)) -> then(cid)
    _ -> wisp.bad_request("invalid CID")
  }
}
