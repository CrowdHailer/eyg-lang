//// Rewrite the locations a stylesheet refers to.
////
//// This is a scanner rather than a parser. It understands just enough CSS,
//// comments, strings, escapes, `url()` and `@import`, to find references.
//// Previews block every location that is not a data URL,
//// so a reference the scanner misses fails to load rather than escaping.

import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string

pub type Reference {
  /// Location in a `url()` function.
  Url(location: String)
  /// Location of a stylesheet in an `@import` rule, as a string or `url()`.
  Import(location: String)
}

/// Replace every reference in `source`.
/// The first error returned by `replace` is returned.
pub fn rewrite(
  source: String,
  replace: fn(Reference) -> Result(String, String),
) -> Result(String, String) {
  let bytes = bit_array.from_string(source)
  let scanner = Scanner(source: bytes, copied: 0, parts: [], replace:)
  use Scanner(parts:, copied:, ..) <- result.try(scan(scanner, bytes, 0, 0))
  let rest = slice(bytes, copied, bit_array.byte_size(bytes))
  [rest, ..parts]
  |> list.reverse
  |> bit_array.concat
  |> bit_array.to_string
  |> result.replace_error("Stylesheet is not valid UTF-8")
}

type Scanner {
  Scanner(
    source: BitArray,
    // byte offset up to which the source has been added to parts
    copied: Int,
    // output in reverse order
    parts: List(BitArray),
    replace: fn(Reference) -> Result(String, String),
  )
}

fn scan(
  scanner: Scanner,
  rest: BitArray,
  offset: Int,
  previous: Int,
) -> Result(Scanner, String) {
  case rest {
    <<"/*", rest:bytes>> ->
      continue(scanner, find_comment_end(rest, offset + 2), 0x2F)
    <<quote, _:bytes>> if quote == 0x22 || quote == 0x27 -> {
      let #(_, end) = read_string(rest, offset)
      continue(scanner, end, quote)
    }
    <<"\\", _, rest:bytes>> -> scan(scanner, rest, offset + 2, 0x41)
    <<"@", a, b, c, d, e, f, after, _:bytes>>
      if { a == 0x69 || a == 0x49 }
      && { b == 0x6D || b == 0x4D }
      && { c == 0x70 || c == 0x50 }
      && { d == 0x6F || d == 0x4F }
      && { e == 0x72 || e == 0x52 }
      && { f == 0x74 || f == 0x54 }
    ->
      case is_name(after) {
        True -> scan(scanner, drop(rest, 1), offset + 1, 0x40)
        False -> import_rule(scanner, offset + 7)
      }
    <<u, r, l, "(", _:bytes>>
      if { u == 0x75 || u == 0x55 }
      && { r == 0x72 || r == 0x52 }
      && { l == 0x6C || l == 0x4C }
    ->
      case is_name(previous) {
        True -> scan(scanner, drop(rest, 1), offset + 1, u)
        False -> {
          use #(location, end) <- stop_unless(
            read_url(scanner.source, offset + 4),
            scanner,
          )
          use scanner <- result.try(substitute(
            scanner,
            offset,
            end,
            Url(location),
          ))
          continue(scanner, end, 0x29)
        }
      }
    <<byte, rest:bytes>> -> scan(scanner, rest, offset + 1, byte)
    _ -> Ok(scanner)
  }
}

/// Bytes that continue an identifier, any non ASCII byte is part of a name.
fn is_name(byte) {
  { byte >= 0x30 && byte <= 0x39 }
  || { byte >= 0x41 && byte <= 0x5A }
  || { byte >= 0x61 && byte <= 0x7A }
  || byte == 0x2D
  || byte == 0x5F
  || byte >= 0x80
}

fn continue(scanner: Scanner, offset, previous) {
  scan(scanner, drop(scanner.source, offset), offset, previous)
}

// Only the first location of an import is a stylesheet, media queries follow.
fn import_rule(scanner: Scanner, offset) {
  let start = skip_space(scanner.source, offset)
  case drop(scanner.source, start) {
    <<quote, _:bytes>> as rest if quote == 0x22 || quote == 0x27 -> {
      let #(location, end) = read_string(rest, start)
      use scanner <- result.try(substitute(
        scanner,
        start,
        end,
        Import(location),
      ))
      continue(scanner, end, quote)
    }
    <<u, r, l, "(", _:bytes>>
      if { u == 0x75 || u == 0x55 }
      && { r == 0x72 || r == 0x52 }
      && { l == 0x6C || l == 0x4C }
    -> {
      use #(location, end) <- stop_unless(
        read_url(scanner.source, start + 4),
        scanner,
      )
      use scanner <- result.try(substitute(
        scanner,
        start,
        end,
        Import(location),
      ))
      continue(scanner, end, 0x29)
    }
    _ -> continue(scanner, start, 0x20)
  }
}

// An unclosed `url(` is invalid CSS, the rest of the stylesheet is kept as it is.
fn stop_unless(result, scanner, then) {
  case result {
    Ok(value) -> then(value)
    Error(Nil) -> Ok(scanner)
  }
}

fn substitute(scanner: Scanner, start, end, reference) {
  let Scanner(source:, copied:, parts:, replace:) = scanner
  use location <- result.map(replace(reference))
  let replacement = case reference {
    Url(..) -> "url(" <> quote(location) <> ")"
    Import(..) -> quote(location)
  }
  let parts = [
    bit_array.from_string(replacement),
    slice(source, copied, start),
    ..parts
  ]
  Scanner(..scanner, copied: end, parts:)
}

fn quote(location) {
  let escaped =
    location
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\a ")
  "\"" <> escaped <> "\""
}

fn find_comment_end(rest, offset) {
  case rest {
    <<>> -> offset
    <<"*/", _:bytes>> -> offset + 2
    <<_, rest:bytes>> -> find_comment_end(rest, offset + 1)
    _ -> offset
  }
}

/// Read a quoted string starting at its opening quote.
/// Returns the unescaped value and the offset after the closing quote.
/// An unescaped newline or the end of input also ends the string.
fn read_string(rest, offset) {
  let assert <<quote, rest:bytes>> = rest
  read_string_value(rest, quote, offset + 1, [])
}

fn read_string_value(rest, quote, offset, acc) {
  case rest {
    <<>> -> #(join(acc), offset)
    <<"\n", _:bytes>> -> #(join(acc), offset)
    <<byte, _:bytes>> if byte == quote -> #(join(acc), offset + 1)
    <<"\\", _:bytes>> -> {
      let #(value, rest, offset) = read_escape(rest, offset)
      read_string_value(rest, quote, offset, [value, ..acc])
    }
    <<byte, rest:bytes>> ->
      read_string_value(rest, quote, offset + 1, [<<byte>>, ..acc])
    _ -> #(join(acc), offset)
  }
}

/// Read a `url(` argument, starting after the open bracket.
/// Returns the location and the offset after the closing bracket.
fn read_url(source, offset) {
  let offset = skip_space(source, offset)
  case drop(source, offset) {
    <<quote, _:bytes>> as rest if quote == 0x22 || quote == 0x27 -> {
      let #(location, end) = read_string(rest, offset)
      let end = skip_space(source, end)
      case drop(source, end) {
        <<")", _:bytes>> -> Ok(#(location, end + 1))
        _ -> Error(Nil)
      }
    }
    rest -> read_unquoted_url(rest, offset, [])
  }
}

fn read_unquoted_url(rest, offset, acc) {
  case rest {
    <<")", _:bytes>> -> Ok(#(string.trim_end(join(acc)), offset + 1))
    <<"\\", _:bytes>> -> {
      let #(value, rest, offset) = read_escape(rest, offset)
      read_unquoted_url(rest, offset, [value, ..acc])
    }
    <<byte, rest:bytes>> ->
      read_unquoted_url(rest, offset + 1, [<<byte>>, ..acc])
    _ -> Error(Nil)
  }
}

/// Read an escape starting at its backslash.
fn read_escape(rest, offset) {
  case rest {
    <<"\\\r\n", rest:bytes>> -> #(<<>>, rest, offset + 3)
    <<"\\\n", rest:bytes>> -> #(<<>>, rest, offset + 2)
    <<"\\", rest:bytes>> ->
      case read_hex(rest, 0, 0) {
        #(0, _) ->
          case rest {
            <<byte, rest:bytes>> -> #(<<byte>>, rest, offset + 2)
            _ -> #(<<>>, rest, offset + 1)
          }
        #(digits, codepoint) -> {
          let rest = drop(rest, digits)
          let #(rest, offset) = case rest {
            <<" ", rest:bytes>> | <<"\t", rest:bytes>> | <<"\n", rest:bytes>> -> #(
              rest,
              offset + digits + 2,
            )
            _ -> #(rest, offset + digits + 1)
          }
          let value = case string.utf_codepoint(codepoint) {
            Ok(codepoint) ->
              bit_array.from_string(string.from_utf_codepoints([codepoint]))
            Error(Nil) -> <<"\u{FFFD}":utf8>>
          }
          #(value, rest, offset)
        }
      }
    _ -> #(<<>>, rest, offset)
  }
}

fn read_hex(rest, digits, value) {
  case digits < 6, rest {
    True, <<byte, rest:bytes>> ->
      case hex_value(byte) {
        Ok(n) -> read_hex(rest, digits + 1, value * 16 + n)
        Error(Nil) -> #(digits, value)
      }
    _, _ -> #(digits, value)
  }
}

fn hex_value(byte) {
  case byte {
    _ if byte >= 0x30 && byte <= 0x39 -> Ok(byte - 0x30)
    _ if byte >= 0x41 && byte <= 0x46 -> Ok(byte - 0x37)
    _ if byte >= 0x61 && byte <= 0x66 -> Ok(byte - 0x57)
    _ -> Error(Nil)
  }
}

fn skip_space(source, offset) {
  case drop(source, offset) {
    <<byte, _:bytes>>
      if byte == 0x20
      || byte == 0x09
      || byte == 0x0A
      || byte == 0x0D
      || byte == 0x0C
    -> skip_space(source, offset + 1)
    <<"/*", _:bytes>> as rest ->
      skip_space(source, find_comment_end(drop(rest, 2), offset + 2))
    _ -> offset
  }
}

fn join(acc) {
  acc
  |> list.reverse
  |> bit_array.concat
  |> bit_array.to_string
  |> result.unwrap("\u{FFFD}")
}

fn drop(bytes, offset) {
  slice(bytes, offset, bit_array.byte_size(bytes))
}

fn slice(bytes, start, end) {
  bit_array.slice(bytes, start, end - start)
  |> result.unwrap(<<>>)
}
