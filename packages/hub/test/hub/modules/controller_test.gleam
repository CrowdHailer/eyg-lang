import eyg/hub/client
import eyg/hub/publisher
import eyg/hub/schema
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/crypto
import gleam/http
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import hub/cid
import hub/fixtures
import hub/generators as g
import hub/helpers.{dispatch}
import hub/modules/data as modules
import hub/packages/data as packages
import hub/router
import ogre/operation
import pog
import wisp/simulate

pub fn share_valid_fragment_test() {
  use context <- helpers.web_context()
  let source = ir.let_("x", ir.integer(0), ir.variable("x"))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
  let assert Ok(cid) = client.share_response(response)
  assert cid.from_tree(source) == cid

  let response = dispatch(client.fetch_module_operation(cid), context)
  assert response.status == 200
  assert json.parse_bits(response.body, dag_json.decoder(Nil)) == Ok(source)
}

pub fn reject_json_string_with_nul_test() {
  use context <- helpers.web_context()
  let source = ir.string("before\u{0000}after")
  let response = dispatch(client.share_module(source), context)
  assert response.status == 422
  assert json.parse_bits(response.body, schema.failure_decoder())
    == Ok("unsupported Unicode escape sequence")
}

pub fn share_fragment_is_idempotent_test() {
  use context <- helpers.web_context()
  let source = ir.let_("x", ir.integer(0), ir.variable("x"))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
}

pub fn share_records_the_proxy_client_ip_test() {
  use context <- helpers.web_context()
  let source = ir.let_("x", ir.integer(0), ir.variable("x"))
  let body = dag_json.to_data_model(source) |> json.to_string
  let request =
    simulate.request(http.Post, "/modules/share")
    |> simulate.string_body(body)
    |> request.set_header("content-type", "application/json")
    |> request.set_header("x-forwarded-for", "10.0.0.1, 192.0.2.1")

  assert router.route(request, context).status == 200
  let assert Ok(pog.Returned(rows: [1], ..)) =
    pog.execute(modules.count_uploads_by_ip("192.0.2.1"), context.db)
}

pub fn share_bundle_test() {
  use context <- helpers.web_context()
  let archive = test_bundle()
  let assert #(#(root, _), [#(dependency, _)]) = archive
  let response = share_bundle(archive, context)

  assert response.status == 200
  assert client.share_response(response) == Ok(root)
  assert fetch_status(dependency, context) == 200
}

pub fn share_bundle_with_shared_dependency_test() {
  use context <- helpers.web_context()
  let leaf = unique_identity()
  let leaf_cid = cid.from_tree(leaf)
  let left = ir.let_("left", unique_value(), ir.reference(leaf_cid))
  let left_cid = cid.from_tree(left)
  let right = ir.let_("right", unique_value(), ir.reference(leaf_cid))
  let right_cid = cid.from_tree(right)
  let root_source =
    ir.let_(
      "left",
      ir.reference(left_cid),
      ir.apply(ir.reference(right_cid), ir.integer(1)),
    )
  let root = cid.from_tree(root_source)
  let archive = #(#(root, root_source), [
    #(right_cid, right),
    #(left_cid, left),
    #(leaf_cid, leaf),
  ])

  assert share_bundle(archive, context).status == 200
}

pub fn share_bundle_with_published_dependency_test() {
  use context <- helpers.web_context()
  let dependency = unique_value()
  let dependency_cid = cid.from_tree(dependency)
  assert dispatch(client.share_module(dependency), context).status == 200
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)
  let package = g.package()
  let release =
    publisher.first(signatory.entity, keypair.key_id, package, dependency_cid)
  let assert Ok(_) = pog.execute(packages.insert_release(release), context.db)
  let source = ir.release(package, 1, dependency_cid)

  assert share_bundle(single_bundle(source), context).status == 200
}

pub fn reject_bundle_atomically_when_dependency_is_missing_test() {
  use context <- helpers.web_context()
  let dependency = unique_value()
  let dependency_cid = cid.from_tree(dependency)
  let source =
    ir.let_(
      "dependency",
      ir.reference(dependency_cid),
      ir.release(g.package(), 1, helpers.random_cid()),
    )
  let root = cid.from_tree(source)
  let archive = #(#(root, source), [#(dependency_cid, dependency)])

  assert share_bundle(archive, context).status == 422
  assert fetch_status(root, context) == 204
  assert fetch_status(dependency_cid, context) == 204
}

pub fn reject_bundle_with_mismatched_pinned_dependency_test() {
  use context <- helpers.web_context()
  let published = unique_value()
  let published_cid = cid.from_tree(published)
  assert dispatch(client.share_module(published), context).status == 200
  let substituted = ir.integer(0)
  let substituted_cid = cid.from_tree(substituted)
  assert dispatch(client.share_module(substituted), context).status == 200
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)
  let package = g.package()
  let release =
    publisher.first(signatory.entity, keypair.key_id, package, published_cid)
  let assert Ok(_) = pog.execute(packages.insert_release(release), context.db)
  let source = ir.release(package, 1, substituted_cid)

  assert share_bundle(single_bundle(source), context).status == 422
}

pub fn share_shakes_unreachable_bundle_block_test() {
  use context <- helpers.web_context()
  let #(root, dependencies) = test_bundle()
  let invalid = ir.variable("missing")
  let invalid_cid = cid.from_tree(invalid)
  let archive = #(root, [#(invalid_cid, invalid), ..dependencies])

  assert share_bundle(archive, context).status == 200
  assert fetch_status(invalid_cid, context) == 204
}

pub fn accept_already_stored_bundle_block_test() {
  use context <- helpers.web_context()
  let archive = test_bundle()
  let assert #(root_module, [#(_, dependency)]) = archive
  assert dispatch(client.share_module(dependency), context).status == 200

  assert share_bundle(archive, context).status == 200
  assert share_bundle(#(root_module, []), context).status == 200
}

pub fn reject_unsound_bundle_modules_test() {
  use context <- helpers.web_context()

  assert share_bundle(single_bundle(ir.variable("missing")), context).status
    == 422
  assert bundle_with_dependency(ir.variable("missing"))
    |> share_bundle(context)
    |> fn(response) { response.status }
    == 422
}

pub fn reject_bundle_root_with_noncanonical_json_test() {
  use context <- helpers.web_context()
  let source = unique_value()
  // The raw bytes have a valid hash, but storage drops the whitespace.
  let block = <<" ", dag_json.to_block(source):bits>>
  let root = cid.from_block(block)
  assert root != cid.from_tree(source)

  let response =
    dispatch(client.share_bundle_operation(#(#(root, block), [])), context)
  assert response.status == 422
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

pub fn can_reference_by_content_test() {
  use context <- helpers.web_context()
  let source = ir.integer(int.random(1_000_000))
  let assert Ok(cid) = fixtures.insert_module(context.db, source)

  let source = ir.add(ir.reference(cid), ir.integer(1))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
}

pub fn can_reference_shared_transitive_module_test() {
  use context <- helpers.web_context()
  let assert Ok(leaf) = fixtures.insert_module(context.db, ir.integer(1))
  let assert Ok(left) =
    fixtures.insert_module(
      context.db,
      ir.add(ir.reference(leaf), ir.integer(1)),
    )
  let assert Ok(right) =
    fixtures.insert_module(
      context.db,
      ir.add(ir.reference(leaf), ir.integer(2)),
    )

  let source = ir.add(ir.reference(left), ir.reference(right))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
}

pub fn fails_with_invalid_type_content_reference_test() {
  use context <- helpers.web_context()
  let source = ir.string("")
  let assert Ok(cid) = fixtures.insert_module(context.db, source)

  let source = ir.add(ir.reference(cid), ir.integer(1))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 422
}

pub fn can_reference_by_release_test() {
  use context <- helpers.web_context()
  let source = ir.integer(int.random(1_000_000))
  let package = g.package()
  let cid = fixtures.first_package(context.db, package, source)

  let source = ir.add(ir.release(package, 1, cid), ir.integer(1))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
}

pub fn fails_with_invalid_type_release_reference_test() {
  use context <- helpers.web_context()
  let source = ir.string("")
  let package = g.package()
  let cid = fixtures.first_package(context.db, package, source)

  let source = ir.add(ir.release(package, 1, cid), ir.integer(1))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 422
}

pub fn rejects_conflicting_pin_for_cached_release_test() {
  use context <- helpers.web_context()
  let package = g.package()
  let cid = fixtures.first_package(context.db, package, ir.integer(1))

  let source =
    ir.add(
      ir.release(package, 1, cid),
      ir.release(package, 1, helpers.random_cid()),
    )
  let response = dispatch(client.share_module(source), context)
  assert response.status == 422
}

pub fn reject_too_large_fragment_test() {
  let source = ir.string(string.repeat("a", 500_000))
  use context <- helpers.web_context()
  let response = dispatch(client.share_module(source), context)
  assert response.status == 413
}

pub fn accept_large_fragment_test() {
  let source = ir.string(string.repeat("a", 499_980))
  use context <- helpers.web_context()
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
}

pub fn fetch_nonexistant_fragment_test() {
  use context <- helpers.web_context()
  let response =
    dispatch(client.fetch_module_operation(dag_json.vacant_cid), context)
  assert response.status == 204
}

pub fn fetch_with_invalid_cid_test() {
  use context <- helpers.web_context()
  let operation = operation.get("/modules/xyz")
  let response = dispatch(operation, context)
  assert response.status == 400
}

fn test_bundle() {
  let dependency = unique_value()
  bundle_with_dependency(dependency)
}

fn unique_value() {
  ir.binary(crypto.strong_random_bytes(40))
}

fn unique_identity() {
  ir.let_("nonce", unique_value(), ir.lambda("x", ir.variable("x")))
}

fn share_bundle(archive, context) {
  dispatch(bundle_operation(archive), context)
}

fn bundle_operation(archive) {
  let #(#(root, source), dependencies) = archive
  let dependencies =
    list.map(dependencies, fn(module) {
      let #(cid, source) = module
      #(cid, dag_json.to_block(source))
    })
  client.share_bundle_operation(#(
    #(root, dag_json.to_block(source)),
    dependencies,
  ))
}

fn single_bundle(source) {
  let root = cid.from_tree(source)
  #(#(root, source), [])
}

fn bundle_with_dependency(dependency) {
  let dependency_cid = cid.from_tree(dependency)
  let source = ir.reference(dependency_cid)
  #(#(cid.from_tree(source), source), [#(dependency_cid, dependency)])
}

fn fetch_status(cid, context) {
  dispatch(client.fetch_module_operation(cid), context).status
}
