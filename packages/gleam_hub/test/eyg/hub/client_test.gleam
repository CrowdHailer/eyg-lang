import eyg/hub/client
import eyg/hub/schema
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/http/response
import gleam/json
import gleam/option.{None}
import midas/continuation
import ogre/origin

pub fn fetch_accepts_content_with_the_requested_cid_test() {
  let source = ir.record([#("count", ir.integer(43))])
  let requested = module_cid(source)
  let response =
    response.new(200) |> response.set_body(dag_json.to_block(source))
  let result =
    client.fetch_module(
      requested,
      origin.Origin(http.Http, "example.com", None),
      fn(_) { continuation.return(Ok(response)) },
      hash_sha256,
    )(fn(value) { value })

  assert result == Ok(source)
}

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
      hash_sha256,
    )(fn(value) { value })

  assert result == Error("hub returned a module with the wrong content ID")
}

fn hash_sha256(_algorithm, bytes) {
  continuation.return(crypto.hash(crypto.Sha256, bytes))
}

pub fn share_rejects_an_incorrect_response_cid_test() {
  let root_source = ir.integer(1)
  let root = module_cid(root_source)
  let other = module_cid(ir.integer(2))
  let response =
    response.new(200)
    |> response.set_body(
      schema.share_response_encode(other)
      |> json.to_string
      |> bit_array.from_string,
    )
  let result =
    client.share_bundle(
      #(#(root, dag_json.to_block(root_source)), []),
      origin.Origin(http.Http, "example.com", None),
      fn(_) { continuation.return(Ok(response)) },
    )(fn(value) { value })

  assert result == Error("hub returned the wrong shared module ID")
}

fn module_cid(source) {
  cid.from_tree(source, fn(bytes) {
    continuation.return(crypto.hash(crypto.Sha256, bytes))
  })(fn(cid) { cid })
}
