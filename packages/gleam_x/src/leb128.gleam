import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list

pub fn encode_unsigned(value) {
  do_encode_unsigned(value, [])
}

fn do_encode_unsigned(value, acc) {
  case value {
    v if v < 0 -> Error(Nil)
    v if v < 128 ->
      [<<0:1, v:7>>, ..acc]
      |> list.reverse
      |> bit_array.concat
      |> Ok
    v -> do_encode_unsigned(v / 128, [<<1:1, { v % 128 }:7>>, ..acc])
  }
}

pub fn decode_unsigned(bytes: BitArray) -> Result(#(Int, BitArray), Nil) {
  let assert Ok(max) = int.power(2, 53.0)
  do_decode_unsigned(bytes, 0, 1, float.round(max))
}

fn do_decode_unsigned(bytes, value, scale, limit) {
  // limit stops:
  // 
  // 1. returned value being too hight to be represented on JavaScript
  // 2. scale building so hight that infinities get involved on JavaScript
  // 3. bad input causing long runtimes.
  case bytes {
    <<more:1, low:7, rest:bytes>> -> {
      let value = value + low * scale
      case more {
        0 ->
          case value < limit {
            True -> Ok(#(value, rest))
            False -> Error(Nil)
          }
        _ -> {
          let scale = scale * 128
          case scale < limit {
            True -> do_decode_unsigned(rest, value, scale, limit)
            False -> Error(Nil)
          }
        }
      }
    }
    _ -> Error(Nil)
  }
}
