import eyg/hub/client
import eyg/hub/publisher
import gleam/option.{None, Some}
import hub/crypto
import hub/fixtures
import hub/generators as g
import hub/helpers.{dispatch}
import ogre/operation
import untethered/ledger/server
import untethered/substrate

pub fn submit_first_release_test() {
  use context <- helpers.web_context()
  let package = g.package()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)
  let assert Ok(Nil) = fixtures.own_package(context.db, package, signatory.cid)

  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(signatory.cid, keypair.key_id, package, module)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, keypair)

  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)

  let assert Ok(Ok(response)) = client.submit_package_response(response)
  let cid = response.cid
  assert cid == response.entity
  assert 1 == response.sequence
  assert None == response.previous
  assert "release" == response.type_
}

pub fn reject_not_first_release_test() {
  use context <- helpers.web_context()
  let package = g.package()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)

  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(signatory.cid, keypair.key_id, package, module)
  let first = substrate.Entry(..first, sequence: 2)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, keypair)

  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)

  let assert Ok(Error(reason)) = client.submit_package_response(response)
  assert server.denied_reason(server.MissingPrevious) == reason
}

pub fn reject_publish_with_nonexistant_fragment_test() {
  use context <- helpers.web_context()
  let package = g.package()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)
  let assert Ok(Nil) = fixtures.own_package(context.db, package, signatory.cid)

  let module = helpers.random_cid()
  let first = publisher.first(signatory.cid, keypair.key_id, package, module)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, keypair)
  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)

  let assert Ok(Error(reason)) = client.submit_package_response(response)
  assert "package_entries_module_fkey" == reason
}

pub fn second_release_test() {
  use context <- helpers.web_context()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)

  let package = g.package()
  let assert Ok(Nil) = fixtures.own_package(context.db, package, signatory.cid)
  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(signatory.cid, keypair.key_id, package, module)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, keypair)

  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)
  let assert Ok(Ok(response)) = client.submit_package_response(response)
  let entity_cid = response.cid

  let entry =
    publisher.follow(signatory.cid, keypair.key_id, package, module, response)
  let payload = publisher.to_bytes(entry)
  let signature = crypto.sign(payload, keypair)

  let request = client.submit_package(entry, signature)
  let response = dispatch(request, context)
  let assert Ok(Ok(response)) = client.submit_package_response(response)

  assert entity_cid == response.entity
  assert 2 == response.sequence
  assert Some(entity_cid) == response.previous
  assert "release" == response.type_
}

pub fn reject_publish_without_ownership_test() {
  use context <- helpers.web_context()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)

  // No ownership has been granted for this package name, so even a valid
  // signatory may not publish under it.
  let package = g.package()
  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(signatory.cid, keypair.key_id, package, module)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, keypair)

  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)

  let assert Ok(Error(reason)) = client.submit_package_response(response)
  assert server.denied_reason(server.DoesNotHavePermission) == reason
}

pub fn owner_endpoint_returns_current_owner_test() {
  use context <- helpers.web_context()
  let package = g.package()
  let assert Ok(#(signatory, _keypair)) = fixtures.signatory(context.db)
  let assert Ok(Nil) = fixtures.own_package(context.db, package, signatory.cid)

  let response =
    dispatch(operation.get("/packages/" <> package <> "/owner"), context)
  assert response.status == 200
}

pub fn owner_endpoint_404_for_unowned_package_test() {
  use context <- helpers.web_context()
  let response =
    dispatch(operation.get("/packages/" <> g.package() <> "/owner"), context)
  assert response.status == 404
}

pub fn reject_publish_by_non_owner_test() {
  use context <- helpers.web_context()
  let package = g.package()

  // Alice is granted ownership of the package name.
  let assert Ok(#(alice, _alice_keypair)) = fixtures.signatory(context.db)
  let assert Ok(Nil) = fixtures.own_package(context.db, package, alice.cid)

  // Eve is a different signatory entity and was never granted ownership.
  let assert Ok(#(eve, eve_keypair)) = fixtures.signatory(context.db)
  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(eve.cid, eve_keypair.key_id, package, module)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, eve_keypair)

  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)

  let assert Ok(Error(reason)) = client.submit_package_response(response)
  assert server.denied_reason(server.DoesNotHavePermission) == reason
}

pub fn reject_publish_by_previous_owner_test() {
  use context <- helpers.web_context()
  let package = g.package()

  // Eve is a different signatory entity and was previously granted ownership.
  let assert Ok(#(eve, eve_keypair)) = fixtures.signatory(context.db)
  let assert Ok(module) = fixtures.module(context.db)
  let assert Ok(Nil) = fixtures.own_package(context.db, package, eve.cid)

  // Alice is granted ownership of the package name.
  let assert Ok(#(alice, _alice_keypair)) = fixtures.signatory(context.db)
  let assert Ok(Nil) = fixtures.own_package(context.db, package, alice.cid)

  let first = publisher.first(eve.cid, eve_keypair.key_id, package, module)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, eve_keypair)

  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)

  let assert Ok(Error(reason)) = client.submit_package_response(response)
  assert server.denied_reason(server.DoesNotHavePermission) == reason
}
