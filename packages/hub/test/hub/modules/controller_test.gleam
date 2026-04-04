import eyg/hub/client
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/http
import gleam/http/request
import gleam/string
import hub/helpers.{dispatch}
import hub/router
import hub/web/utils
import ogre/operation
import wisp/simulate

pub fn share_valid_fragment_test() {
  use context <- helpers.web_context()
  let source = ir.let_("x", ir.integer(0), ir.variable("x"))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
  let assert Ok(cid) = client.share_response(response)
  assert utils.cid_from_tree(source) == cid

  let response = dispatch(client.get_module(cid), context)
  assert response.status == 200
  assert dag_json.from_block(response.body) == Ok(source)
}

pub fn share_fragment_is_idempotent_test() {
  use context <- helpers.web_context()
  let source = ir.let_("x", ir.integer(0), ir.variable("x"))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
}

pub fn reject_invalid_json_test() {
  use context <- helpers.web_context()
  let block = <<"not json!">>
  let request =
    simulate.request(http.Post, "/modules/share")
    |> simulate.bit_array_body(block)
    |> request.set_header("content-type", "application/json")
  let response = router.route(request, context)
  assert response.status == 400
}

pub fn reject_invalid_ast_test() {
  use context <- helpers.web_context()
  let block = <<"{}">>
  let request =
    simulate.request(http.Post, "/modules/share")
    |> simulate.bit_array_body(block)
    |> request.set_header("content-type", "application/json")
  let response = router.route(request, context)
  assert response.status == 400
}

pub fn reject_unsound_fragment_test() {
  use context <- helpers.web_context()
  let source = ir.let_("x", ir.integer(0), ir.variable("y"))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 422
}

pub fn reject_impure_fragment_test() {
  let source = ir.call(ir.perform("Log"), [ir.string("hello")])
  use context <- helpers.web_context()
  let response = dispatch(client.share_module(source), context)
  assert response.status == 422
}

pub fn reject_too_large_fragment_test() {
  let source = ir.string(string.repeat("a", 50_000))
  use context <- helpers.web_context()
  let response = dispatch(client.share_module(source), context)
  assert response.status == 413
}

pub fn accept_large_fragment_test() {
  let source = ir.string(string.repeat("a", 49_980))
  use context <- helpers.web_context()
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
}

pub fn fetch_nonexistant_fragment_test() {
  use context <- helpers.web_context()
  let response = dispatch(client.get_module(dag_json.vacant_cid), context)
  assert response.status == 204
}

pub fn fetch_with_invalid_cid_test() {
  use context <- helpers.web_context()
  let operation = operation.get("/modules/xyz")
  let response = dispatch(operation, context)
  assert response.status == 400
}
