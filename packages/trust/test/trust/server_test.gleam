import dag_json
import gleam/json
import gleam/option.{Some}
import multiformats/cid/v1
import multiformats/hashes
import trust/client
import trust/protocol/signatory
import trust/server
import trust/substrate.{Entry}

pub fn validate_first_payload_test() {
  let entry = signatory.first("key_abc")
  let assert Ok(parsed) = validate_payload(signatory.to_bytes(entry))
  assert entry == parsed
}

pub fn validate_subsequent_payload_test() {
  let entry =
    Entry(
      sequence: 7,
      previous: Some(random_cid()),
      signatory: Nil,
      key: "key_aa",
      content: signatory.AddKey("key_aa"),
    )
  let assert Ok(parsed) = validate_payload(signatory.to_bytes(entry))
  assert entry == parsed
}

pub fn invalid_json_payload_test() {
  let assert Error(reason) = validate_payload(<<>>)
  assert server.DecodeError(json.UnexpectedEndOfInput) == reason
}

pub fn cant_submit_zero_sequence_entry_test() {
  let entry = Entry(..signatory.first("key_abc"), sequence: 0)
  let assert Error(reason) = validate_payload(signatory.to_bytes(entry))

  assert server.InvalidSequence == reason
}

pub fn first_sequence_must_be_1_test() {
  let entry = Entry(..signatory.first("key_abc"), sequence: 2)
  let assert Error(reason) = validate_payload(signatory.to_bytes(entry))
  assert server.MissingPrevious == reason
}

pub fn cant_submit_with_unexpected_previous_test() {
  let entry = Entry(..signatory.first("key_abc"), previous: Some(random_cid()))
  let assert Error(reason) = validate_payload(signatory.to_bytes(entry))
  assert server.UnexpectedPrevious == reason
}

pub fn validate_integrity_test() {
  let previous = signatory.first("key_abc")
  let proposed =
    Entry(
      sequence: 2,
      previous: Some(random_cid()),
      signatory: random_cid(),
      key: "key_abc",
      content: signatory.AddKey("key_aa"),
    )
  let assert Ok(Nil) = server.validate_integrity(proposed, previous)
}

pub fn must_step_sequence_test() {
  let previous = signatory.first("key_abc")
  let proposed =
    Entry(
      sequence: 7,
      previous: Some(random_cid()),
      signatory: random_cid(),
      key: "key_abc",
      content: signatory.AddKey("key_aa"),
    )
  let assert Error(reason) = server.validate_integrity(proposed, previous)
  assert server.WrongSequence == reason
}

// TODO move to signatory/archive
fn validate_payload(bytes) {
  server.validate_payload(
    bytes,
    substrate.intrinsic_decoder(signatory.event_decoder()),
  )
}

fn random_cid() {
  v1.Cid(dag_json.code(), hashes.Multihash(hashes.Sha256, <<>>))
}
