import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/schema
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import hub/cid
import hub/modules/data
import hub/server/context.{type Context}
import hub/web/utils
import multiformats/cid/v1
import pog
import wisp

pub fn share(
  request: Request(wisp.Connection),
  context: Context,
) -> Response(wisp.Body) {
  let request = wisp.set_max_body_size(request, 50_000)
  use <- wisp.require_content_type(request, "application/json")
  use data <- wisp.require_string_body(request)
  use source <- utils.do_decode(data, dag_json.decoder(Nil))
  use <- check_soundness(source, context.db)
  let ip = uploaded_by(request)

  let cid = cid.from_tree(source)
  use _ <- utils.db_result(pog.execute(data.insert(cid, source, ip), context.db))
  wisp.ok()
  |> wisp.json_body(json.to_string(schema.share_response_encode(cid)))
}

fn uploaded_by(request: Request(wisp.Connection)) -> String {
  request.get_header(request, "x-forwarded-for")
  |> result.unwrap("0.0.0.0")
  |> string.split(",")
  |> list.last
  |> result.map(string.trim)
  |> result.unwrap("0.0.0.0")
}

fn check_soundness(source, db, then) {
  let analysis =
    infer.pure()
    |> infer.check(source)
    |> resolve_check(db)
  case analysis {
    Ok(analysis) ->
      case infer.all_errors(analysis) {
        [] -> then()
        _ -> wisp.unprocessable_content()
      }
    Error(_) -> wisp.response(503)
  }
}

// cache can contain errors, the returned errors can if we want extend the error messages sent to the client
// errors should accumulate just in case. 
// bundle checking can work on top of cache/acc in this function
fn resolve_check(
  step: infer.Step(infer.Analysis(Nil)),
  db: pog.Connection,
) -> Result(infer.Analysis(Nil), pog.QueryError) {
  case step {
    infer.Done(analysis) -> Ok(analysis)
    infer.Lookup(ir.Content(cid), resume) -> {
      let query = data.get(v1.to_string(cid))
      case pog.execute(query, db) {
        Ok(pog.Returned(rows: [module], ..)) -> {
          // remove the assertion and test on corrupted data.
          let assert Ok(source) =
            json.parse(module.source, dag_json.decoder(Nil))
          // Errors should be added to returned response
          use analysis <- result.try(
            infer.pure()
            |> infer.check(source)
            |> resolve_check(db),
          )
          let type_ = infer.poly_type(analysis)
          resolve_check(resume(Ok(type_)), db)
        }
        Ok(pog.Returned(rows: [], ..)) -> resolve_check(resume(Error(Nil)), db)
        Ok(pog.Returned(rows: _, ..)) -> resolve_check(resume(Error(Nil)), db)
        Error(reason) -> Error(reason)
      }
    }
    infer.Lookup(ir.Package(..), resume) ->
      resolve_check(resume(Error(Nil)), db)
    infer.Lookup(ir.Version(..), resume) ->
      resolve_check(resume(Error(Nil)), db)
    infer.Lookup(ir.Pinned(release: _), resume) ->
      // TODO add lookup of release
      resolve_check(resume(Error(Nil)), db)
    infer.Lookup(ir.Relative(..), resume) ->
      resolve_check(resume(Error(Nil)), db)
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
