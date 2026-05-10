import eyg/hub/client
import eyg/hub/publisher
import gleam/option.{None, Some}
import hub/crypto
import hub/fixtures
import hub/generators as g
import hub/helpers.{dispatch}
import untethered/ledger/server
import untethered/substrate

pub fn submit_first_release_test() {
  use context <- helpers.web_context()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)

  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(signatory.cid, keypair.key_id, "foo", module)
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
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)

  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(signatory.cid, keypair.key_id, "foo", module)
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
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)

  let module = helpers.random_cid()
  let first = publisher.first(signatory.cid, keypair.key_id, "foo", module)
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

pub fn reject_publish_by_different_entity_test() {
  use context <- helpers.web_context()
  let package = g.package()

  let assert Ok(#(alice, alice_keypair)) = fixtures.signatory(context.db)
  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(alice.cid, alice_keypair.key_id, package, module)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, alice_keypair)
  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)
  let assert Ok(Ok(_)) = client.submit_package_response(response)

  let assert Ok(#(eve, eve_keypair)) = fixtures.signatory(context.db)
  let assert Ok(module2) = fixtures.module(context.db)
  let eve_first =
    publisher.first(eve.cid, eve_keypair.key_id, package, module2)
  let payload2 = publisher.to_bytes(eve_first)
  let signature2 = crypto.sign(payload2, eve_keypair)
  let request2 = client.submit_package(eve_first, signature2)
  let response2 = dispatch(request2, context)

  let assert Ok(Error(reason)) = client.submit_package_response(response2)
  assert server.denied_reason(server.DoesNotHavePermission) == reason
}

pub fn allow_owner_to_publish_after_another_package_test() {
  use context <- helpers.web_context()
  let package = g.package()

  let assert Ok(#(alice, alice_keypair)) = fixtures.signatory(context.db)
  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(alice.cid, alice_keypair.key_id, package, module)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, alice_keypair)
  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)
  let assert Ok(Ok(first_response)) = client.submit_package_response(response)

  let assert Ok(module2) = fixtures.module(context.db)
  let second =
    publisher.follow(alice.cid, alice_keypair.key_id, package, module2, first_response)
  let payload2 = publisher.to_bytes(second)
  let signature2 = crypto.sign(payload2, alice_keypair)
  let request2 = client.submit_package(second, signature2)
  let response2 = dispatch(request2, context)

  let assert Ok(Ok(second_response)) = client.submit_package_response(response2)
  assert 2 == second_response.sequence
}
