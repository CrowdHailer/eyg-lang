import eyg/hub/client
import eyg/hub/publisher
import eyg/ir/car
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/string
import hub/cid
import hub/fixtures
import hub/generators as g
import hub/helpers.{dispatch}
import hub/modules/bundle
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

pub fn share_fragment_is_idempotent_test() {
  use context <- helpers.web_context()
  let source = ir.let_("x", ir.integer(0), ir.variable("x"))
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
  let response = dispatch(client.share_module(source), context)
  assert response.status == 200
}

pub fn share_bundle_test() {
  use context <- helpers.web_context()
  let archive = test_bundle()
  let assert bundle.Bundle(
    root: #(root, _),
    dependencies: [#(dependency_cid, _)],
  ) = archive
  let response = share_bundle(archive, context)

  assert response.status == 200
  assert client.share_response(response) == Ok(root)
  let response =
    dispatch(client.fetch_module_operation(dependency_cid), context)
  assert response.status == 200
}

pub fn share_bundle_is_idempotent_test() {
  use context <- helpers.web_context()
  let archive = test_bundle()

  assert share_bundle(archive, context).status == 200
  assert share_bundle(archive, context).status == 200
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
  let archive =
    bundle.Bundle(root: #(root, root_source), dependencies: [
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

pub fn reject_bundle_with_unpublished_pinned_dependency_test() {
  use context <- helpers.web_context()
  let dependency = unique_value()
  let dependency_cid = cid.from_tree(dependency)
  assert dispatch(client.share_module(dependency), context).status == 200
  let source = ir.release(g.package(), 1, dependency_cid)
  let archive =
    bundle.Bundle(root: #(cid.from_tree(source), source), dependencies: [
      #(dependency_cid, dependency),
    ])

  assert share_bundle(archive, context).status == 422
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

pub fn share_root_last_bundle_test() {
  use context <- helpers.web_context()
  let archive = test_bundle()
  let bundle.Bundle(root: #(root, _), ..) = archive
  let blocks = archive_blocks(archive) |> list.reverse
  let archive = car.Car(car.Header(1, [root]), blocks)

  assert share_car(archive, context).status == 200
}

pub fn reject_duplicate_bundle_block_test() {
  use context <- helpers.web_context()
  let assert bundle.Bundle(
    root:,
    dependencies: [dependency, ..] as dependencies,
  ) = test_bundle()
  let archive = bundle.Bundle(root:, dependencies: [dependency, ..dependencies])

  assert share_bundle(archive, context).status == 422
}

pub fn share_shakes_unreachable_bundle_block_test() {
  use context <- helpers.web_context()
  let bundle.Bundle(root:, dependencies:) = test_bundle()
  let invalid = ir.variable("missing")
  let archive =
    bundle.Bundle(root:, dependencies: [
      #(cid.from_tree(invalid), invalid),
      ..dependencies
    ])

  assert share_bundle(archive, context).status == 200
  let response =
    dispatch(client.fetch_module_operation(cid.from_tree(invalid)), context)
  assert response.status == 204
}

pub fn accept_already_stored_bundle_block_test() {
  use context <- helpers.web_context()
  let archive = test_bundle()
  let assert bundle.Bundle(root: root_module, dependencies: [#(_, dependency)]) =
    archive
  assert dispatch(client.share_module(dependency), context).status == 200

  assert share_bundle(archive, context).status == 200
  assert share_bundle(
      bundle.Bundle(root: root_module, dependencies: []),
      context,
    ).status
    == 200
}

pub fn share_json_module_with_stored_dependency_test() {
  use context <- helpers.web_context()
  let archive = test_bundle()
  let assert bundle.Bundle(root: #(_, source), dependencies: [#(_, dependency)]) =
    archive
  assert dispatch(client.share_module(dependency), context).status == 200

  assert dispatch(client.share_module(source), context).status == 200
}

pub fn reject_json_module_with_missing_dependency_test() {
  use context <- helpers.web_context()
  let bundle.Bundle(root: #(_, source), ..) = test_bundle()

  assert dispatch(client.share_module(source), context).status == 422
}

pub fn reject_corrupt_stored_dependency_test() {
  use context <- helpers.web_context()
  let declared = cid.from_tree(unique_value())
  let corrupt = ir.integer(1)
  let assert Ok(_) =
    pog.execute(modules.insert(declared, corrupt, "127.0.0.1"), context.db)
  let source = ir.reference(declared)

  assert dispatch(client.share_module(source), context).status == 500
}

pub fn resharing_repairs_corrupt_stored_source_test() {
  use context <- helpers.web_context()
  let source = unique_value()
  let declared = cid.from_tree(source)
  let corrupt = ir.integer(1)
  let assert Ok(_) =
    pog.execute(modules.insert(declared, corrupt, "127.0.0.1"), context.db)

  assert share_bundle(single_bundle(source), context).status == 200
  let response = dispatch(client.fetch_module_operation(declared), context)
  assert response.status == 200
  assert json.parse_bits(response.body, dag_json.decoder(Nil)) == Ok(source)
}

pub fn reject_bundle_with_missing_block_test() {
  use context <- helpers.web_context()
  let bundle.Bundle(root:, ..) = test_bundle()
  let archive = bundle.Bundle(root:, dependencies: [])

  assert share_bundle(archive, context).status == 422
}

pub fn reject_bundle_with_incorrect_block_cid_test() {
  use context <- helpers.web_context()
  let dependency = ir.integer(1)
  let source = ir.reference(dag_json.vacant_cid)
  let root = cid.from_tree(source)
  let operation =
    client.share_bundle_operation(
      #(#(root, dag_json.to_block(source)), [
        #(dag_json.vacant_cid, dag_json.to_block(dependency)),
      ]),
    )
  let response = dispatch(operation, context)

  assert response.status == 422
}

pub fn reject_noncanonical_bundle_block_test() {
  use context <- helpers.web_context()
  let source = unique_value()
  let block = bit_array.concat([<<" ":utf8>>, dag_json.to_block(source)])
  let root = cid.from_block(block)
  let archive = car.Car(car.Header(1, [root]), [#(root, block)])

  assert share_car(archive, context).status == 422
}

pub fn reject_invalid_car_test() {
  use context <- helpers.web_context()

  assert share_car_body(<<"not a car":utf8>>, context).status == 422
}

pub fn reject_unsupported_car_version_test() {
  use context <- helpers.web_context()
  let root = dag_json.vacant_cid
  let archive = car.Car(car.Header(version: 2, roots: [root]), [])

  assert share_car(archive, context).status == 422
}

pub fn reject_car_without_one_root_test() {
  use context <- helpers.web_context()
  let root = dag_json.vacant_cid

  assert share_car(car.Car(car.Header(1, []), []), context).status == 422
  assert share_car(car.Car(car.Header(1, [root, root]), []), context).status
    == 422
}

pub fn reject_bundle_without_root_block_test() {
  use context <- helpers.web_context()
  let archive = car.Car(car.Header(1, [dag_json.vacant_cid]), [])

  assert share_car(archive, context).status == 422
}

pub fn reject_bundle_with_invalid_module_block_test() {
  use context <- helpers.web_context()
  let block = <<"not a module":utf8>>
  let root = cid.from_block(block)
  let archive = car.Car(car.Header(1, [root]), [#(root, block)])

  assert share_car(archive, context).status == 422
}

pub fn reject_bundle_with_unshareable_reference_test() {
  use context <- helpers.web_context()

  list.each(
    [ir.package("example"), ir.version("example", 1), ir.relative("module")],
    fn(source) {
      assert share_bundle(single_bundle(source), context).status == 422
    },
  )
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

pub fn reject_impure_bundle_modules_test() {
  use context <- helpers.web_context()
  let impure = ir.call(ir.perform("Log"), [ir.string("hello")])

  assert share_bundle(single_bundle(impure), context).status == 422
  assert bundle_with_dependency(impure)
    |> share_bundle(context)
    |> fn(response) { response.status }
    == 422
}

pub fn reject_too_large_bundle_test() {
  use context <- helpers.web_context()
  let body = string.repeat("a", 500_001) |> bit_array.from_string

  assert share_car_body(body, context).status == 413
}

pub fn bundle_content_type_test() {
  use context <- helpers.web_context()
  let archive = single_bundle(unique_value())
  let assert Ok(body) = encode_bundle(archive)

  assert share_car_body_with_type(
      body,
      car.content_type <> "; charset=binary",
      context,
    ).status
    == 200
  assert share_car_body_with_type(body, car.content_type <> "pet", context).status
    == 415
}

fn test_bundle() {
  let dependency = unique_value()
  let dependency_cid = cid.from_tree(dependency)
  let source = ir.reference(dependency_cid)
  bundle.Bundle(root: #(cid.from_tree(source), source), dependencies: [
    #(dependency_cid, dependency),
  ])
}

fn unique_value() {
  ir.binary(crypto.strong_random_bytes(40))
}

fn unique_identity() {
  ir.let_("nonce", unique_value(), ir.lambda("x", ir.variable("x")))
}

fn share_bundle(archive, context) {
  let bundle.Bundle(root: #(root, source), dependencies:) = archive
  let dependencies =
    list.map(dependencies, fn(module) {
      #(module.0, dag_json.to_block(module.1))
    })
  client.share_bundle_operation(#(
    #(root, dag_json.to_block(source)),
    dependencies,
  ))
  |> dispatch(context)
}

fn single_bundle(source) {
  let root = cid.from_tree(source)
  bundle.Bundle(root: #(root, source), dependencies: [])
}

fn bundle_with_dependency(dependency) {
  let dependency_cid = cid.from_tree(dependency)
  let source = ir.reference(dependency_cid)
  let root = cid.from_tree(source)
  bundle.Bundle(root: #(root, source), dependencies: [
    #(dependency_cid, dependency),
  ])
}

fn archive_blocks(archive) {
  bundle.blocks(archive)
  |> list.map(fn(module) { #(module.0, dag_json.to_block(module.1)) })
}

fn encode_bundle(archive) {
  let bundle.Bundle(root: #(root, _), ..) = archive
  car.encode(car.Car(car.Header(1, [root]), archive_blocks(archive)))
}

fn share_car(archive, context) {
  let assert Ok(body) = car.encode(archive)
  share_car_body(body, context)
}

fn share_car_body(body, context) {
  share_car_body_with_type(body, car.content_type, context)
}

fn share_car_body_with_type(body, content_type, context) {
  let request =
    simulate.request(http.Post, "/modules/share")
    |> simulate.bit_array_body(body)
    |> request.set_header("content-type", content_type)
  router.route(request, context)
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
