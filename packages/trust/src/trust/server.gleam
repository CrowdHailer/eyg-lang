import gleam/json
import gleam/option.{None, Some}
import gleam/result
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
  use entry <- result.try(
    case json.parse_bits(bytes, substrate.entry_decoder(decoder)) {
      Ok(entry) -> Ok(entry)
      Error(reason) -> Error(DecodeError(reason))
    },
  )

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
