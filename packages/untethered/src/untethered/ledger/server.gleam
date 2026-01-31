import gleam/dict
import gleam/http/request
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import untethered/protocol/signatory
import untethered/substrate

pub type Denied {
  MissingSignature
  DecodeError(json.DecodeError)
  InvalidSequence
  MissingPrevious
  UnexpectedPrevious
  WrongSequence
  IncorrectPrevious
  UnauthorizedKey
  IncorrectSignature
  DoesNotHavePermission
  // UnknownSignatory
  InvalidSignatorySequence
}

pub fn denied_status_code(reason) {
  case reason {
    MissingSignature -> 401
    DecodeError(_) -> 400
    InvalidSequence -> 400
    MissingPrevious -> 400
    UnexpectedPrevious -> 400
    WrongSequence -> 422
    IncorrectPrevious -> 422
    UnauthorizedKey -> 403
    IncorrectSignature -> 403
    DoesNotHavePermission -> 403
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

pub fn read_signature(request) {
  case request.get_header(request, "authorization") {
    Ok("Signature " <> sig) -> Ok(sig)
    Ok(_) -> Error(MissingSignature)
    Error(Nil) -> Error(MissingSignature)
  }
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
