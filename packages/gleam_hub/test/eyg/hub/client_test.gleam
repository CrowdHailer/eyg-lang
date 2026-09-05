import eyg/hub/client
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/crypto
import gleam/http
import gleam/http/response
import gleam/option.{None}
import midas/continuation
import ogre/origin

pub fn fetch_rejects_content_with_the_wrong_cid_test() {
  let requested = module_cid(ir.integer(1))
  let response =
    response.new(200)
    |> response.set_body(dag_json.to_block(ir.integer(2)))
  let result =
    client.fetch_module(
      requested,
      origin.Origin(http.Http, "example.com", None),
      fn(_) { continuation.return(Ok(response)) },
    )(fn(value) { value })

  assert result == Error("hub returned a module with the wrong content ID")
}

fn module_cid(source) {
  cid.from_tree(source, fn(bytes) {
    continuation.return(crypto.hash(crypto.Sha256, bytes))
  })(fn(cid) { cid })
}
