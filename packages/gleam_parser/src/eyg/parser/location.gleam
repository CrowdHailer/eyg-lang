//// Render source-line context with carets under a span.
////
//// The same renderer is used for parse errors (single position widened into
//// a one-character span) and runtime errors (whole-expression spans). The
//// interpreter does not depend on this module — the CLI calls it after
//// composing the interpreter's description and hint.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string

/// A byte-offset range, inclusive of `start` and exclusive of `end`.
/// `#(0, 0)` is treated as "no location" by callers.
pub type Span =
  #(Int, Int)

/// Returns true when a span carries no location information.
pub fn is_empty(span: Span) -> Bool {
  span == #(0, 0)
}

/// Render the source line(s) containing `span` with carets underneath.
///
/// - A zero-width span (`#(p, p)`) renders a single `^` at column `p`.
/// - A single-line span renders `^` characters spanning the range.
/// - A multi-line span underlines from the start column to the end of the
///   first line, then renders subsequent lines (up to and including the line
///   containing `span.1`) with a row of `^`s underneath each.
pub fn source_context(source: String, span: Span) -> List(String) {
  let #(start, end) = span
  let end = int.max(end, start)
  let bytes = bit_array.from_string(source)
  let lines = split_lines(bytes, bytes, 0, 0, [])
  do_render(lines, start, end, 1, 0, [])
}

// Keep the original byte widths: CRLF is one line ending but two bytes.
// Normalizing source first would invalidate spans after a CRLF.
fn split_lines(source, remaining, start, offset, acc) {
  case remaining {
    <<"\r\n", rest:bits>> ->
      split_lines(source, rest, offset + 2, offset + 2, [
        #(source_line(source, start, offset), 2),
        ..acc
      ])
    <<"\r", rest:bits>> | <<"\n", rest:bits>> ->
      split_lines(source, rest, offset + 1, offset + 1, [
        #(source_line(source, start, offset), 1),
        ..acc
      ])
    <<_, rest:bits>> -> split_lines(source, rest, start, offset + 1, acc)
    _ -> list.reverse([#(source_line(source, start, offset), 0), ..acc])
  }
}

fn source_line(source, start, end) {
  let assert Ok(bytes) = bit_array.slice(source, start, end - start)
  let assert Ok(line) = bit_array.to_string(bytes)
  line
}

fn do_render(
  lines: List(#(String, Int)),
  start: Int,
  end: Int,
  line_num: Int,
  offset: Int,
  acc: List(String),
) -> List(String) {
  case lines {
    [] -> list.reverse(acc)
    [#(line, ending_width), ..rest] -> {
      let line_len = string.byte_size(line)
      let line_end = offset + line_len
      let next_offset = line_end + ending_width
      let line_starts_inside = start <= line_end && end >= offset
      case line_starts_inside, start > line_end {
        // span not yet reached — keep scanning.
        _, True -> do_render(rest, start, end, line_num + 1, next_offset, acc)
        // span has passed — stop rendering.
        False, False -> acc
        True, False -> {
          let caret_start = int.max(0, start - offset)
          let caret_end = int.min(line_len, end - offset)
          // For a zero-width span at the very start of the range, draw a
          // single caret rather than a zero-width underline.
          let width = case start == end {
            True -> 1
            False -> int.max(1, caret_end - caret_start)
          }
          let rendered = render_line(line_num, line, caret_start, width)
          let acc = [rendered, ..acc]
          do_render(rest, start, end, line_num + 1, next_offset, acc)
        }
      }
    }
  }
}

fn render_line(line_num: Int, line: String, col: Int, width: Int) -> String {
  let num_str = int.to_string(line_num)
  let gutter = " " <> num_str <> " | "
  let blank_gutter = string.repeat(" ", string.length(gutter))
  gutter
  <> line
  <> "\n"
  <> blank_gutter
  <> string.repeat(" ", col)
  <> string.repeat("^", width)
}
