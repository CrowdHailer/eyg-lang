import eyg/hub/client
import eyg/hub/publisher
import gleam/option.{None}
import hub/crypto
import hub/fixtures
import hub/helpers.{dispatch}

pub fn submit_first_release_test() {
  use context <- helpers.web_context()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(context.db)

  let assert Ok(module) = fixtures.module(context.db)
  let first = publisher.first(signatory.cid, keypair.key_id, "foo", module)
  let payload = publisher.to_bytes(first)
  let signature = crypto.sign(payload, keypair)

  let request = client.submit_package(first, signature)
  let response = dispatch(request, context)

  let assert Ok(response) = client.submit_package_response(response)
  let cid = response.cid
  assert cid == response.entity
  assert 1 == response.sequence
  assert None == response.previous
  assert "release" == response.type_
}
// pub fn reject_not_first_release_test() {
//   use context <- test_context()
//   let #(signatory, keypair) = th.signatory_fixture(context)

//   let package = "eregerg"
//   let module = th.fragment_fixture(context.db)
//   let first =
//     substrate.Entry(
//       sequence: 1,
//       previous: None,
//       signatory:,
//       key: keypair.key_id,
//       content: publisher.Release(package:, version: 2, module:),
//     )
//   let payload = publisher.to_bytes(first)
//   let signature = crypto.sign(payload, keypair)

//   let request = submit_request(payload, signature)
//   let response = send_bits(request, context)

//   // This should fail
//   let assert Ok(response) = client.submit_response(response)
// }

// // pub fn reject_publish_with_nonexistant_fragment_test() {
// //   use context <- test_context()
// //   use signatory, private <- th.signatory_fixture(context)
// //   let entity = uuid.v4_string()

// //   let source = ir.integer(int.random(1_000_000))
// //   let cid = cid_from_tree(source)

// //   let response = publish(entity, 1, cid, signatory, private, context)
// //   assert response.status == 422
// // }

// pub fn second_release_test() {
//   use context <- test_context()
//   let signatory = th.signatory_fixture(context)
//   let module = th.fragment_fixture(context.db)
//   let package = "boo"
//   let archived = th.release_fixture(signatory, package, module, context.db)

//   let module = th.fragment_fixture(context.db)
//   let second =
//     substrate.Entry(
//       sequence: 2,
//       previous: Some(archived.cid),
//       signatory: signatory.0,
//       key: { signatory.1 }.key_id,
//       content: publisher.Release(package:, version: 2, module:),
//     )
//   let payload = publisher.to_bytes(second)
//   let signature = crypto.sign(payload, signatory.1)

//   let request = submit_request(payload, signature)
//   let response = send_bits(request, context)
//   let assert Ok(response) = client.submit_response(response)
//   echo response
//   todo
// }

// pub fn reject_invalid_json_test() {
//   use context <- test_context()
//   let block = <<"not json!">>
//   let request =
//     simulate.request(http.Post, "/registry/submit")
//     |> simulate.bit_array_body(block)
//     |> request.set_header("authorization", "Signature " <> base32.encode(<<>>))
//     |> request.set_header("content-type", "application/json")
//   let response = router.route(request, context)
//   assert response.status == 400
// }

// pub fn reject_invalid_payload_test() {
//   use context <- test_context()
//   let block = <<"{}">>
//   let request =
//     simulate.request(http.Post, "/registry/submit")
//     |> simulate.bit_array_body(block)
//     |> request.set_header("authorization", "Signature " <> base32.encode(<<>>))
//     |> request.set_header("content-type", "application/json")
//   let response = router.route(request, context)
//   assert response.status == 400
// }

// fn test_context(then) {
//   use context, _ai <- th.test_context()
//   then(context)
// }
// // import gleam/http
// // import gleam/http/request
// // import gleam/http/response.{Response}
// // import gleam/int
// // import gleam/option.{None}
// // import server/apex/registry/router
// // import server/registry/data_test
// // import server/test_helpers
// // import untethered/substrate
// // import website/registry/protocol
// // import wisp/simulate

// // pub type Query {
// //   Query(
// //     // zero if not set
// //     since: Int,
// //     // 1000 if not set
// //     limit: Int,
// //   )
// // }

// // pub fn pull(context, query) {
// //   let request =
// //     simulate.request(http.Get, "/registry/events")
// //     |> request.set_query(query)
// //   let response = router.route(request, context)
// //   let body = simulate.read_body_bits(response)
// //   Response(..response, body:)
// // }

// // pub fn list_events_since_cutoff_test() {
// //   use context <- test_context()
// //   let db = context.db
// //   let cid1 = data_test.fixture_fragment(db)
// //   let assert Ok(e1) = data.write_release(db, "abc", 1, todo as cid1)
// //   let cid2 = data_test.fixture_fragment(db)
// //   let assert Ok(_e2) = data.write_release(db, "pqr", 1, todo as cid2)
// //   let cid3 = data_test.fixture_fragment(db)
// //   let assert Ok(_e3) = data.write_release(db, "abc", 2, todo as cid3)

// //   let cid1 = data_test.fragment_fixture(db)
// //   let assert Ok(e1) = data_test.fixture_release("abc", 1, None, cid1, db)
// //   let cid2 = data_test.fragment_fixture(db)
// //   let assert Ok(_) = data_test.fixture_release("pgr", 1, None, cid2, db)
// //   let cid3 = data_test.fragment_fixture(db)
// //   let assert Ok(_) = data_test.fixture_release("abc", 2, None, cid3, db)
// //   todo
// //   // let assert Ok(response) = protocol.pull_events_response(pull(context, []))
// //   // let assert [substrate.Entry("abc", 1, ..), _, _] = response.events

// //   // let assert Ok(response) =
// //   //   protocol.pull_events_response(pull(context, [#("limit", "2")]))
// //   // let assert [substrate.Entry("abc", 1, ..), _] = response.events
// //   // let assert Ok(response) =
// //   //   protocol.pull_events_response(
// //   //     pull(context, [#("since", int.to_string(e1)), #("limit", "1")]),
// //   //   )
// //   // let assert [substrate.Entry("pgr", 1, ..)] = response.events
// // }

// // // list events for given event
// // fn test_context(then) {
// //   use context, _ai <- test_helpers.test_context()
// //   then(context)
// // }
