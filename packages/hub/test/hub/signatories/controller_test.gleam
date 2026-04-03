import eyg/hub/client
import eyg/hub/signatory
import gleam/option.{None, Some}
import hub/cid
import hub/crypto
import hub/helpers.{dispatch}
import untethered/ledger/schema
import untethered/substrate

pub fn create_and_modify_signatory_test() {
  use context <- helpers.web_context()
  let keypair = crypto.generate_key()

  let first = signatory.first(keypair.key_id)
  let payload = signatory.to_bytes(first)
  let signature = crypto.sign(payload, keypair)
  let cid = cid.from_block(payload)

  let request = client.submit_signatory(first, signature)
  let response = dispatch(request, context)
  let assert Ok(response) = client.submit_signatory_response(response)

  let cursor = response.cursor
  assert cid == response.entity
  assert 1 == response.sequence
  assert cid == response.cid

  let request = client.pull_signatories(schema.pull_parameters())
  let response = dispatch(request, context)
  let assert Ok(response) = client.pull_signatories_response(response)

  let assert [entry] = response.entries
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
  let assert Ok(response) = client.submit_signatory_response(response)

  assert cursor + 1 == response.cursor
  assert cid == response.entity
  assert 2 == response.sequence
  assert cid2 == response.cid
}
// pub fn submit_without_incorrect_authorization_kind_test() {
//   use context <- test_context()
//   let keypair = crypto.generate_key()

//   let first = signatory.first(keypair.key_id)
//   let payload = signatory.to_bytes(first)
//   let signature = crypto.sign(payload, keypair)

//   let endpoint = #(origin, "/signatory/submit")
//   let request =
//     client.submit_request(endpoint, payload, signature)
//     |> request.set_header("authorization", "Bearer " <> signature)
//   let response = send_bits(request, router.route(_, context))

//   assert 401 == response.status
// }

// pub fn deny_submit_with_wrong_signature_test() {
//   use context <- test_context()
//   let keypair = crypto.generate_key()

//   let first = signatory.first(keypair.key_id)
//   let payload = signatory.to_bytes(first)
//   let signature = base32.encode(<<"notarealsignature">>)

//   let endpoint = #(origin, "/signatory/submit")
//   let request = client.submit_request(endpoint, payload, signature)
//   let response = send_bits(request, router.route(_, context))

//   assert 403 == response.status
// }

// pub fn deny_first_entry_with_another_key_test() {
//   use context <- test_context()
//   let keypair = crypto.generate_key()

//   let first = signatory.first(keypair.key_id)
//   let another = crypto.generate_key()
//   let first =
//     substrate.Entry(..first, content: signatory.AddKey(another.key_id))
//   let payload = signatory.to_bytes(first)
//   let signature = crypto.sign(payload, keypair)

//   let endpoint = #(origin, "/signatory/submit")
//   let request = client.submit_request(endpoint, payload, signature)
//   let response = send_bits(request, router.route(_, context))

//   assert 403 == response.status
// }

// // pub fn cant_create_subsequent_with_wrong_key_test() {
// //   use context <- test_context()
// //   use alice, _alice_private <- identity_fixture(context)
// //   use eve, eve_private <- identity_fixture(context)

// //   // eve tries to sign an update to alices entity
// //   substrate.cid_from_entry(alice, trust.event_encode)
// //   let second =
// //     substrate.Entry(
// //       // entity: alice.entity,
// //       sequence: 2,
// //       previous: Some(cid_from_entry(alice, trust.event_encode)),
// //       // eve signs adding eves key
// //       signatory: substrate.Signatory(..eve.signatory, sequence: 1),
// //       content: trust.AddKey(eve.signatory.key),
// //     )

// //   let response = submit(second, eve_private, context)
// //   assert 403 == response.status

// //   // eve pretends her key is a member of alices entity
// //   let second =
// //     substrate.Entry(
// //       // entity: alice.entity,
// //       sequence: 2,
// //       previous: Some(cid_from_entry(alice, trust.event_encode)),
// //       // eve signs adding eves key
// //       signatory: substrate.Signatory(
// //         entity: todo as "alice.entity",
// //         sequence: 1,
// //         key: eve.signatory.key,
// //       ),
// //       content: trust.AddKey(eve.signatory.key),
// //     )

// //   let response = submit(second, eve_private, context)
// //   assert 403 == response.status
// // }

// // pub fn cant_create_subsequent_without_previous_test() {
// //   use context <- test_context()
// //   use first, private <- identity_fixture(context)
// //   let second =
// //     substrate.Entry(
// //       // entity: todo as "first.entity",
// //       sequence: 2,
// //       previous: None,
// //       signatory: substrate.Signatory(..first.signatory, sequence: 1),
// //       content: trust.AddKey(first.signatory.key),
// //     )

// //   let response = submit(second, private, context)
// //   assert 422 == response.status
// // }

// // // pub fn cant_create_subsequent_with_wrong_previous_test() {
// // //   use context <- test_context()
// // //   use first, private <- identity_fixture(context)
// // //   let second =
// // //     substrate.Entry(
// // //       entity: first.entity,
// // //       sequence: 2,
// // //       previous: Some(v1.Cid(
// // //         dag_json.code(),
// // //         todo as "sha256.digest(<<\"{}\">>)",
// // //       )),
// // //       signatory: substrate.Signatory(..first.signatory, sequence: 1),
// // //       content: trust.AddKey(first.signatory.key),
// // //     )

// // //   let response = submit(second, private, context)
// // //   assert 422 == response.status
// // // }

// // // Can't add same key again

// fn test_context(then) {
//   use context, _ai <- test_helpers.test_context()
//   then(context)
// }
