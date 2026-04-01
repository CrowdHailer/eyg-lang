import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/publisher
import eyg/hub/schema
import eyg/hub/signatory
import eyg/ir/dag_json
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import hub/registry/data
import hub/server/context.{type Context}
import hub/web/utils
import multiformats/cid/v1
import pog

// import pog
// import server/apex/context
// import server/crypto
// import server/helpers.{cid_from_tree}
// import server/registry/data
// import server/signatory/data as sig_data
// import server/web/utils
// import untethered/ledger/schema
import untethered/ledger/server
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
  echo request
  let ip = ""
  wisp.accepted

  let cid = utils.cid_from_tree(source)
  case pog.execute(data.insert_module(cid, source, ip), context.db) {
    Ok(_) ->
      wisp.ok()
      |> wisp.json_body(json.to_string(schema.share_response_encode(cid)))

    Error(_) -> todo
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

pub fn module(cid, context) {
  use _cid <- decode_cid(cid)

  let context.Context(db:, ..) = context
  let query =
    pog.query("SELECT 42;")
    |> pog.returning({
      use number <- decode.field(0, decode.int)
      decode.success(number)
    })
  let assert Ok(returned) = pog.execute(query, db)
  assert [42] == returned.rows
  echo 42
  // use fragment <- utils.db_call(data.get_fragment(db, cid))
  // case fragment {
  //   Some(fragment) ->
  //     wisp.response(200)
  //     |> wisp.string_body(fragment.source)
  //   None -> wisp.not_found()
  // }
  wisp.not_found()
}

fn decode_cid(cid, then) {
  case v1.from_string(cid) {
    Ok(#(cid, <<>>)) -> then(cid)
    _ -> wisp.bad_request("invalid CID")
  }
}
