import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/schema
import eyg/ir/dag_json
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/string
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
  use <- wisp.require_content_type(request, "application/json")
  use data <- wisp.require_string_body(request)
  use <- check_size(data, 50_000)
  use source <- utils.do_decode(data, dag_json.decoder(Nil))
  use <- check_soundness(source)
  use <- check_purity(source)
  // echo request
  let ip = "123.1.1.1"
  // wisp.accepted

  let cid = utils.cid_from_tree(source)
  case pog.execute(data.insert(cid, source, ip), context.db) {
    Ok(_) ->
      wisp.ok()
      |> wisp.json_body(json.to_string(schema.share_response_encode(cid)))

    Error(_reason) -> wisp.internal_server_error()
  }
}

fn check_size(data, max, then) {
  case string.byte_size(data) <= max {
    True -> then()
    False -> wisp.content_too_large()
  }
}

fn check_soundness(source, then) {
  let inference = infer.unpure() |> infer.check(source)
  case infer.all_errors(inference) {
    [] -> then()
    _ -> wisp.unprocessable_content()
  }
}

fn check_purity(source, then) {
  let inference = infer.pure() |> infer.check(source)
  case infer.all_errors(inference) {
    [] -> then()
    _ -> wisp.unprocessable_content()
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
    Error(_reason) -> wisp.internal_server_error()
  }
}

fn decode_cid(cid, then) {
  case v1.from_string(cid) {
    Ok(#(cid, <<>>)) -> then(cid)
    _ -> wisp.bad_request("invalid CID")
  }
}
