import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/hub/schema
import eyg/ir/car
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
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

const max_upload = 500_000

pub fn share(
  request: Request(wisp.Connection),
  context: Context,
) -> Response(wisp.Body) {
  let request = wisp.set_max_body_size(request, max_upload)
  case utils.content_type(request) {
    Ok("application/json") -> share_module(request, context)
    Ok("application/vnd.ipld.car") -> share_bundle(request, context)
    _ ->
      wisp.unsupported_media_type(accept: ["application/json", car.content_type])
  }
}

fn share_module(
  request: Request(wisp.Connection),
  context: Context,
) -> Response(wisp.Body) {
  use source_text <- wisp.require_string_body(request)
  use source <- utils.do_decode(source_text, dag_json.decoder(Nil))
  let root = cid.from_tree(source)
  process_bundle(#(#(root, source), []), context, uploaded_by(request))
}

fn share_bundle(
  request: Request(wisp.Connection),
  context: Context,
) -> Response(wisp.Body) {
  use body <- wisp.require_bit_array_body(request)
  case car.decode(body) {
    Ok(file) ->
      case bundle.from_car(file) {
        Ok(bundle) -> process_bundle(bundle, context, uploaded_by(request))
        Error(reason) -> utils.api_reason(422, reason)
      }
    Error(reason) -> utils.api_reason(400, reason)
  }
}

fn process_bundle(bundle, context: Context, ip) {
  let #(#(cid, source), deps) = bundle
  let modules = list.reverse([#(cid, source), ..deps])
  case check_all(modules, empty(), context.db) {
    Ok(Nil) -> {
      use _ <- utils.db_result(pog.execute(
        data.insert_bundle(modules, ip),
        context.db,
      ))

      wisp.ok()
      |> wisp.json_body(json.to_string(schema.share_response_encode(cid)))
    }
    Error(Unsound(_)) -> utils.api_reason(422, "unsound")
    Error(LookupFailed(_)) -> utils.api_reason(503, "db unavailable")
  }
}

type CheckError {
  Unsound(List(#(Nil, error.Reason)))
  LookupFailed(pog.QueryError)
}

fn check_all(modules, cache: Cache, db) {
  case modules {
    [] -> Ok(Nil)
    [#(cid, source), ..rest] -> {
      case check_single(source, cache, db) {
        Ok(#(type_, cache)) -> {
          let modules = dict.insert(cache.modules, cid, Ok(type_))
          let cache = Cache(..cache, modules:)
          check_all(rest, cache, db)
        }
        Error(reason) -> Error(reason)
      }
    }
  }
}

fn check_single(
  source: ir.Node(Nil),
  cache: Cache,
  db: pog.Connection,
) -> Result(#(binding.Poly, Cache), CheckError) {
  let analysis =
    infer.pure()
    |> infer.check(source)
    |> resolve_check(cache, db)
  case analysis {
    Ok(#(analysis, cache)) ->
      case infer.all_errors(analysis) {
        [] -> Ok(#(infer.poly_type(analysis), cache))
        errors -> Error(Unsound(errors))
      }
    Error(reason) -> Error(LookupFailed(reason))
  }
}

fn uploaded_by(request: Request(wisp.Connection)) -> String {
  request.get_header(request, "x-forwarded-for")
  |> result.unwrap("0.0.0.0")
  |> string.split(",")
  |> list.last
  |> result.map(string.trim)
  |> result.unwrap("0.0.0.0")
}

type Cache {
  Cache(
    modules: dict.Dict(v1.Cid, Result(binding.Poly, Nil)),
    releases: dict.Dict(ir.Release, Result(binding.Poly, Nil)),
  )
}

fn empty() {
  Cache(dict.new(), dict.new())
}

fn resolve_check(
  step: infer.Step(infer.Analysis(Nil)),
  cache: Cache,
  db: pog.Connection,
) -> Result(#(infer.Analysis(Nil), Cache), pog.QueryError) {
  case step {
    infer.Done(analysis) -> Ok(#(analysis, cache))
    infer.Lookup(ir.Content(cid), resume) -> {
      use #(result, cache) <- result.try(resolve_module(cid, cache, db))
      resolve_check(resume(result), cache, db)
    }
    infer.Lookup(ir.Package(..), resume) ->
      resolve_check(resume(Error(Nil)), cache, db)
    infer.Lookup(ir.Version(..), resume) ->
      resolve_check(resume(Error(Nil)), cache, db)
    infer.Lookup(ir.Pinned(release:), resume) -> {
      use #(result, cache) <- result.try(resolve_release(release, cache, db))
      resolve_check(resume(result), cache, db)
    }
    infer.Lookup(ir.Relative(..), resume) ->
      resolve_check(resume(Error(Nil)), cache, db)
  }
}

fn resolve_release(
  release: ir.Release,
  cache: Cache,
  db: pog.Connection,
) -> Result(#(Result(binding.Poly, Nil), Cache), pog.QueryError) {
  let Cache(releases:, ..) = cache

  case dict.get(releases, release) {
    Ok(cid) -> Ok(#(cid, cache))
    Error(_) -> {
      let query = packages.get_release(release.package, release.version)
      use #(found, cache) <- result.try(case pog.execute(query, db) {
        Ok(pog.Returned(rows: [found], ..)) -> {
          let cid = release.module
          case v1.to_string(cid) == found.module {
            True -> resolve_module(cid, cache, db)
            False -> Ok(#(Error(Nil), cache))
          }
        }
        Ok(pog.Returned(rows: [], ..)) -> Ok(#(Error(Nil), cache))
        Ok(pog.Returned(rows: _, ..)) -> Ok(#(Error(Nil), cache))
        Error(reason) -> Error(reason)
      })
      let releases = dict.insert(cache.releases, release, found)
      let cache = Cache(..cache, releases:)
      Ok(#(found, cache))
    }
  }
}

fn resolve_module(
  cid: v1.Cid,
  cache: Cache,
  db: pog.Connection,
) -> Result(#(Result(binding.Poly, Nil), Cache), pog.QueryError) {
  case dict.get(cache.modules, cid) {
    Ok(result) -> Ok(#(result, cache))
    Error(_) -> {
      let query = data.get(v1.to_string(cid))
      use #(found, cache) <- result.try(case pog.execute(query, db) {
        Ok(pog.Returned(rows: [module], ..)) -> {
          case json.parse(module.source, dag_json.decoder(Nil)) {
            Ok(source) -> {
              use #(analysis, cache) <- result.try(
                infer.pure()
                |> infer.check(source)
                |> resolve_check(cache, db),
              )
              // We assume no errors in loaded module
              let type_ = infer.poly_type(analysis)
              Ok(#(Ok(type_), cache))
            }
            Error(json.UnableToDecode(errors)) ->
              Error(pog.UnexpectedResultType(errors))
            // Other errors should not be possible as the value was stored in a JSON column.
            Error(_) -> Error(pog.UnexpectedResultType([]))
          }
        }
        Ok(pog.Returned(rows: [], ..)) -> Ok(#(Error(Nil), cache))
        Ok(pog.Returned(rows: _, ..)) -> Ok(#(Error(Nil), cache))
        Error(reason) -> Error(reason)
      })
      let modules = dict.insert(cache.modules, cid, found)
      let cache = Cache(..cache, modules:)
      Ok(#(found, cache))
    }
  }
}

pub fn get(cid: String, context: Context) -> Response(wisp.Body) {
  use _cid <- decode_cid(cid)
  case pog.execute(data.get(cid), context.db) {
    Ok(pog.Returned(rows: [module], ..)) ->
      wisp.ok()
      |> wisp.json_body(module.source)
    Ok(pog.Returned(rows: [], ..)) -> wisp.no_content()
    Ok(_) -> wisp.internal_server_error()
    Error(_reason) -> wisp.response(503)
  }
}

fn decode_cid(cid, then) {
  case v1.from_string(cid) {
    Ok(#(cid, <<>>)) -> then(cid)
    _ -> wisp.bad_request("invalid CID")
  }
}
