import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import untethered/ledger/server
import untethered/substrate.{Entry}

pub fn validate_first_payload_test() {
  let payload = <<
    "{\"sequence\":1,\"previous\":null,\"key\":\"\",\"type\":\"foo\",\"content\":\"FOO\"}",
  >>
  assert Ok(Entry(1, None, Nil, "", "FOO"))
    == server.validate_payload(payload, decoder())
}

pub fn not_json_failure_test() {
  let payload = <<>>
  let assert Error(reason) = server.validate_payload(payload, decoder())
  assert server.DecodeError(json.UnexpectedEndOfInput) == reason
}

pub fn invalid_entry_failure_test() {
  let payload = <<"{}">>
  let assert Error(reason) = server.validate_payload(payload, decoder())
  let assert server.DecodeError(json.UnableToDecode(..)) = reason
}

pub fn cant_submit_zero_sequence_entry_test() {
  let payload = <<
    "{\"sequence\":0,\"previous\":null,\"key\":\"\",\"type\":\"foo\",\"content\":\"FOO\"}",
  >>
  let assert Error(reason) = server.validate_payload(payload, decoder())
  assert server.InvalidSequence == reason
}

pub fn first_sequence_must_be_1_test() {
  let payload = <<
    "{\"sequence\":2,\"previous\":null,\"key\":\"\",\"type\":\"foo\",\"content\":\"FOO\"}",
  >>
  let assert Error(reason) = server.validate_payload(payload, decoder())
  assert server.MissingPrevious == reason
}

fn decoder() {
  substrate.intrinsic_decoder(fn(key) {
    case key {
      "foo" -> decode.string
      _ -> decode.success("TODO")
    }
  })
}

pub fn validate_subsequent_payload_test() {
  let payload = <<
    "{\"sequence\":2,\"previous\":",
    "{\"/\":\"baguqeerar6vyjqns54f63oywkgsjsnrcnuiixwgrik2iovsp7mdr6wplmsma\"}",
    ",\"key\":\"\",\"type\":\"foo\",\"content\":\"FOO\"}",
  >>
  let assert Ok(Entry(2, Some(_), Nil, "", "FOO")) =
    server.validate_payload(payload, decoder())
}

pub fn cant_submit_with_unexpected_previous_test() {
  let payload = <<
    "{\"sequence\":1,\"previous\":",
    "{\"/\":\"baguqeerar6vyjqns54f63oywkgsjsnrcnuiixwgrik2iovsp7mdr6wplmsma\"}",
    ",\"key\":\"\",\"type\":\"foo\",\"content\":\"FOO\"}",
  >>
  let assert Error(reason) = server.validate_payload(payload, decoder())
  assert server.UnexpectedPrevious == reason
}
