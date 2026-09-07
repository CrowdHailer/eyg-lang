import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/schema
import eyg/ir/dag_json
import gleam/dict
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
  use <- check_soundness(source)
  let ip = uploaded_by(request)

  let cid = cid.from_tree(source)
  case pog.execute(data.insert(cid, source, ip), context.db) {
    Ok(_) ->
      wisp.ok()
      |> wisp.json_body(json.to_string(schema.share_response_encode(cid)))

    Error(_reason) -> wisp.internal_server_error()
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

fn check_soundness(source, then) {
  let inference =
    infer.pure() |> infer.check_with_references(dict.new(), source)
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
