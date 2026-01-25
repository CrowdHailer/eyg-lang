import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import trust/protocol/signatory
import trust/substrate

pub type Denied {
  DecodeError(json.DecodeError)
  InvalidSequence
  MissingPrevious
  UnexpectedPrevious
  WrongSequence
  IncorrectPrevious
  UnauthorizedKey
  IncorrectSignature
  DoesNotHaveAccess
  // UnknownSignatory
  InvalidSignatorySequence
}

pub fn denied_status_code(reason) {
  case reason {
    DecodeError(_) -> 400
    InvalidSequence -> 400
    MissingPrevious -> 400
    UnexpectedPrevious -> 400
    WrongSequence -> 422
    IncorrectPrevious -> 422
    UnauthorizedKey -> 403
    IncorrectSignature -> 403
    DoesNotHaveAccess -> 403
    InvalidSignatorySequence -> 403
  }
}

/// Check that the bytes represent a valid entry.
/// Pass in the content decoder for your protocol
/// 
/// 1. Checks payload is a valid JSON entry.
/// 2. Checks sequence is 1 and previous is null.
/// 3. Checks sequence is > 1 and previous is not null.
pub fn validate_payload(bytes, decoder) {
  use entry <- result.try(case json.parse_bits(bytes, decoder) {
    Ok(entry) -> Ok(entry)
    Error(reason) -> Error(DecodeError(reason))
  })

  let substrate.Entry(sequence:, previous:, ..) = entry
  use Nil <- result.try(case sequence, previous {
    sequence, _ if sequence < 1 -> Error(InvalidSequence)
    1, None -> Ok(Nil)
    1, Some(_) -> Error(UnexpectedPrevious)
    _sequence, Some(_) -> Ok(Nil)
    _sequence, None -> Error(MissingPrevious)
  })
  Ok(entry)
}

/// Checks that the entry is consistent with the previous entry
/// Pass in previous entry looked up by the proposed entry's previous cid.
/// 
pub fn validate_integrity(proposed, previous_sequence) {
  let substrate.Entry(sequence:, ..) = proposed
  use Nil <- result.try(case previous_sequence + 1 == sequence {
    True -> Ok(Nil)
    False -> Error(WrongSequence)
  })
  Ok(Nil)
}

pub type Policy {
  AddSelf(key: String)
  Admin
}

pub fn fetch_permissions(key, history) {
  let keys = signatory.state(history)
  case history, dict.get(keys, key) {
    [], Error(Nil) -> Ok(AddSelf(key))
    [], Ok(_) -> panic
    // All keys have the same permissions
    _, Ok(Nil) -> Ok(Admin)
    _, Error(Nil) -> Error(UnauthorizedKey)
  }
}

pub type PullParameters {
  PullParameters(since: Int, limit: Int, entities: List(String))
}

pub fn pull_parameters_from_query(query) {
  let since =
    list.key_find(query, "since")
    |> result.try(int.parse)
    |> result.unwrap(0)

  let limit =
    list.key_find(query, "limit")
    |> result.try(int.parse)
    |> result.unwrap(1000)

  let entities =
    list.key_find(query, "entities")
    |> result.map(string.split(_, ","))
    |> result.unwrap([])
  PullParameters(since:, limit:, entities:)
}
