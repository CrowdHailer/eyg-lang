//// The parts of the protobuf wire format that UnixFS use:

import gleam/bit_array
import gleam/list
import gleam/result.{try}
import leb128

pub type Field {
  /// Wire type 0.
  Varint(Int)
  /// Wire type 2: bytes, a string or an embedded message.
  Bytes(BitArray)
}

/// A varint field. `value` must not be negative.
pub fn varint_field(field: Int, value: Int) -> Result(BitArray, Nil) {
  use tag <- try(leb128.encode_unsigned(field * 8))
  use value <- try(leb128.encode_unsigned(value))
  Ok(<<tag:bits, value:bits>>)
}

/// A length-delimited field.
pub fn bytes_field(field: Int, bytes: BitArray) -> Result(BitArray, Nil) {
  use tag <- try(leb128.encode_unsigned(field * 8 + 2))
  use length <- try(leb128.encode_unsigned(bit_array.byte_size(bytes)))
  Ok(<<tag:bits, length:bits, bytes:bits>>)
}

/// The fields of a message in the order they appear, by field number.
pub fn decode(bytes: BitArray) -> Result(List(#(Int, Field)), Nil) {
  do_decode(bytes, [])
}

fn do_decode(bytes, acc) {
  case bytes {
    <<>> -> Ok(list.reverse(acc))
    _ -> {
      use #(tag, rest) <- try(leb128.decode_unsigned(bytes))
      // We don't validate field numbers. However unexpected field numbers will be discarded when searching for fields
      let field = tag / 8
      case tag % 8 {
        0 -> {
          use #(value, rest) <- try(leb128.decode_unsigned(rest))
          do_decode(rest, [#(field, Varint(value)), ..acc])
        }
        2 -> {
          use #(length, rest) <- try(leb128.decode_unsigned(rest))
          case rest {
            <<value:bytes-size(length), rest:bytes>> ->
              do_decode(rest, [#(field, Bytes(value)), ..acc])
            _ -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    }
  }
}
