import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/publisher
import eyg/hub/schema
import eyg/hub/signatory
import eyg/ir/dag_json
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import hub/web/utils
import multiformats/cid/v1

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

pub fn share(request, context) {
  use <- wisp.require_content_type(request, "application/json")
  use data <- wisp.require_string_body(request)
  use <- check_size(data, 50_000)
  use source <- utils.do_decode(data, dag_json.decoder(Nil))
  use <- check_soundness(source)
  use <- check_purity(source)

  let cid = utils.cid_from_tree(source)
  // let context.Context(db:, ..) = context
  // let serialized = dag_json.to_string(source)
  // use fragment <- utils.db_call(data.insert_fragment(db, serialized, cid))
  wisp.ok()
  |> wisp.json_body(json.to_string(schema.share_response_encode(cid)))
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
