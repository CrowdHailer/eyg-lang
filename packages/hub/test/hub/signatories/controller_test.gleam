import eyg/hub/client
import eyg/hub/signatory
import gleam/list
import gleam/option.{None, Some}
import hub/cid
import hub/crypto
import hub/fixtures
import hub/helpers.{dispatch}
import multiformats/base32
import ogre/operation
import untethered/ledger/schema
import untethered/substrate

pub fn create_and_modify_signatory_test() {
  use context <- helpers.web_context()
  let keypair = crypto.generate_key()

  let first = signatory.first(keypair.key_id)
  let payload = signatory.to_bytes(first)
  let signature = crypto.sign(payload, keypair)

  let request = client.submit_signatory(first, signature)
  let response = dispatch(request, context)
  let assert Ok(Ok(response)) = client.submit_signatory_response(response)

  let cid = cid.from_block(payload)
  let cursor = response.cursor
  assert cid == response.entity
  assert 1 == response.sequence
  assert cid == response.cid

  let request = client.pull_signatories(schema.pull_parameters())
  let response = dispatch(request, context)
  let assert Ok(response) = client.pull_signatories_response(response)

  let assert [entry, ..] = response.entries |> list.reverse
  assert cursor == entry.cursor
  assert cid == entry.cid
  assert entry.cid == entry.entity
  assert 1 == entry.sequence
  assert None == entry.previous
  assert "add_key" == entry.type_

  let another_keypair = crypto.generate_key()

  let second =
    substrate.Entry(
      sequence: 2,
      previous: Some(cid),
      signatory: Nil,
      key: keypair.key_id,
      content: signatory.AddKey(another_keypair.key_id),
    )
  let payload = signatory.to_bytes(second)
  let signature = crypto.sign(payload, keypair)
  let cid2 = cid.from_block(payload)

  let request = client.submit_signatory(second, signature)
  let response = dispatch(request, context)
  let assert Ok(Ok(response)) = client.submit_signatory_response(response)

  assert cursor + 1 == response.cursor
  assert cid == response.entity
  assert 2 == response.sequence
  assert cid2 == response.cid
}

pub fn submit_without_incorrect_authorization_kind_test() {
  use context <- helpers.web_context()
  let keypair = crypto.generate_key()

  let first = signatory.first(keypair.key_id)
  let payload = signatory.to_bytes(first)
  let signature = crypto.sign(payload, keypair)

  let operation =
    client.submit_signatory(first, signature)
    |> operation.set_header("authorization", "Bearer " <> signature)

  let response = dispatch(operation, context)
  let assert Ok(Error(response)) = client.submit_signatory_response(response)
  assert "missing_signature" == response
}

pub fn deny_submit_with_wrong_signature_test() {
  use context <- helpers.web_context()
  let keypair = crypto.generate_key()

  let first = signatory.first(keypair.key_id)
  let signature = base32.encode(<<"notarealsignature">>)

  let operation = client.submit_signatory(first, signature)

  let response = dispatch(operation, context)
  let assert Ok(Error(response)) = client.submit_signatory_response(response)
  assert "incorrect_signature" == response
}

pub fn deny_first_entry_with_another_key_test() {
  use context <- helpers.web_context()
  let keypair = crypto.generate_key()

  let first = signatory.first(keypair.key_id)
  let another = crypto.generate_key()
  let first =
    substrate.Entry(..first, content: signatory.AddKey(another.key_id))
  let payload = signatory.to_bytes(first)
  let signature = crypto.sign(payload, keypair)

  let operation = client.submit_signatory(first, signature)

  let response = dispatch(operation, context)
  let assert Ok(Error(response)) = client.submit_signatory_response(response)
  assert "does_not_have_permission" == response
}

pub fn cant_create_subsequent_with_wrong_key_test() {
  use context <- helpers.web_context()
  let assert Ok(#(alice, _alice_keypair)) = fixtures.signatory(context.db)
  let assert Ok(#(_eve, eve_keypair)) = fixtures.signatory(context.db)

  let second =
    substrate.Entry(
      sequence: 2,
      previous: Some(alice.cid),
      // eve signs adding eves key
      signatory: Nil,
      content: signatory.AddKey(eve_keypair.key_id),
      key: eve_keypair.key_id,
    )
  let payload = signatory.to_bytes(second)
  let signature = crypto.sign(payload, eve_keypair)
  let operation = client.submit_signatory(second, signature)
  let response = dispatch(operation, context)
  let assert Ok(Error(response)) = client.submit_signatory_response(response)
  assert "does_not_have_permission" == response
}
