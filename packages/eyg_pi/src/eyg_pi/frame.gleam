//// Decode QEMU's RGB PPM frames and inspect console cells in Gleam.

import gleam/bit_array
import gleam/int
import gleam/list

pub type Image {
  Image(width: Int, height: Int, pixels: BitArray)
}

pub fn decode(bytes) {
  let #(magic, bytes) = token(bytes)
  assert magic == "P6"
  let #(width, bytes) = token(bytes)
  let #(height, bytes) = token(bytes)
  let #(maximum, bytes) = token(bytes)
  assert maximum == "255"
  let assert Ok(width) = int.parse(width)
  let assert Ok(height) = int.parse(height)
  assert bit_array.byte_size(bytes) == width * height * 3
  Image(width, height, bytes)
}

fn token(bytes) {
  let bytes = whitespace(bytes)
  word(bytes, "")
}

fn whitespace(bytes) {
  case bytes {
    <<byte:8, rest:bits>>
      if byte == 10 || byte == 13 || byte == 32 || byte == 9
    -> whitespace(rest)
    _ -> bytes
  }
}

fn word(bytes, text) {
  let assert <<byte:8, rest:bits>> = bytes
  case byte == 10 || byte == 13 || byte == 32 || byte == 9 {
    True -> #(text, rest)
    False -> {
      let assert Ok(char) = bit_array.to_string(<<byte:8>>)
      word(rest, text <> char)
    }
  }
}

pub fn lit(image: Image, col, row, top_only) {
  let rows = case top_only {
    True -> 12
    False -> 16
  }
  list.fold(range(0, rows - 1), 0, fn(count, dy) {
    list.fold(range(0, 7), count, fn(count, dx) {
      let x = col * 8 + dx
      let y = row * 16 + dy
      case x >= 0 && y >= 0 && x < image.width && y < image.height {
        False -> count
        True -> {
          let offset = { y * image.width + x } * 3
          let assert Ok(pixel) = bit_array.slice(image.pixels, offset, 3)
          let assert <<r:8, g:8, b:8>> = pixel
          case r + g + b > 300 {
            True -> count + 1
            False -> count
          }
        }
      }
    })
  })
}

pub fn game(image: Image) {
  let balls =
    list.flat_map(range(0, 19), fn(y) {
      list.filter_map(range(2, 57), fn(x) {
        case lit(image, x + 1, y + 2, False) > 0 {
          True -> Ok(#(x, y))
          False -> Error(Nil)
        }
      })
    })
  let paddle =
    list.filter(range(0, 19), fn(y) { lit(image, 2, y + 2, False) > 0 })
  #(list.last(balls), list.first(paddle))
}

/// The last nonempty console row is an empty prompt, excluding its underline.
pub fn prompt(image: Image) {
  let occupied =
    list.filter(range(0, image.height / 16 - 1), fn(row) {
      list.any(range(0, 11), fn(col) { lit(image, col, row, False) > 0 })
    })
  case list.last(occupied) {
    Error(_) -> False
    Ok(row) ->
      lit(image, 0, row, True) > 0
      && lit(image, 2, row, True) == 0
      && list.all(range(3, 11), fn(col) { lit(image, col, row, False) == 0 })
  }
}

pub fn field(image: Image) {
  list.all(range(0, 19), fn(row) { lit(image, 0, row + 2, True) > 0 })
}

pub fn range(from, to) {
  case from > to {
    True -> []
    False -> [from, ..range(from + 1, to)]
  }
}
