import eyg/ir/tree as ir
import eyg/parser/lexer
import eyg/parser/parser
import eyg/parser/token
import gleam/int
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub fn from_string(src) {
  src
  |> lexer.lex()
  |> token.drop_whitespace()
  |> token.drop_comments()
  |> parser.expression()
}

pub fn all_from_string(src) {
  use #(source, remaining) <- result.try(from_string(src))
  case remaining {
    [] -> Ok(source)
    [#(tok, at), ..] -> Error(parser.TrailingTokens(tok, at))
  }
}

pub fn block_from_string(src) {
  let parsed =
    src
    |> lexer.lex()
    |> token.drop_whitespace()
    |> token.drop_comments()
    |> parser.block()
  case parsed {
    Ok(#(exp, left)) -> Ok(#(do_gather(exp, []), left))
    Error(reason) -> Error(reason)
  }
}

fn do_gather(exp, acc) {
  let #(exp, span) = exp
  case exp {
    ir.Let(label, value, then) ->
      do_gather(then, [#(label, value, span), ..acc])
    ir.Vacant -> #(acc, None)
    _ -> #(acc, Some(#(exp, span)))
  }
}

/// Format a parse error as a human-readable string, showing the relevant
/// source line with a pointer to the error location.
pub fn format_error(reason: parser.Reason, source: String) -> String {
  let description = parser.describe_reason(reason)
  case reason_position(reason) {
    None -> "error: " <> description
    Some(pos) ->
      "error: " <> description <> "\n\n" <> source_context(source, pos)
  }
}

fn reason_position(reason: parser.Reason) -> option.Option(Int) {
  case reason {
    parser.UnexpectedToken(_, pos) -> Some(pos)
    parser.UnexpectEnd -> None
    parser.MissingEquals(pos) -> Some(pos)
    parser.MissingArrow(pos) -> Some(pos)
    parser.UnclosedFunctionBody(open_at) -> Some(open_at)
    parser.ExpectedEffectName(_, pos) -> Some(pos)
    parser.ExpectedBuiltinName(pos) -> Some(pos)
    parser.InvalidCidReference(pos) -> Some(pos)
    parser.InvalidImportPath(pos) -> Some(pos)
    parser.TrailingTokens(_, pos) -> Some(pos)
    parser.InvalidCharacter(_, pos) -> Some(pos)
    parser.UnterminatedStringLiteral(pos) -> Some(pos)
    parser.InvalidEscapeSequence(_, pos) -> Some(pos)
  }
}

fn source_context(source: String, pos: Int) -> String {
  let lines = string.split(source, "\n")
  do_source_context(lines, pos, 1, 0)
}

fn do_source_context(
  lines: List(String),
  target: Int,
  line_num: Int,
  offset: Int,
) -> String {
  case lines {
    [] -> ""
    [line, ..rest] -> {
      let line_len = string.byte_size(line)
      let line_end = offset + line_len
      case target <= line_end {
        True -> {
          let col = int.max(0, target - offset)
          let num_str = int.to_string(line_num)
          let gutter = " " <> num_str <> " | "
          let blank_gutter = string.repeat(" ", string.length(gutter))
          gutter
          <> line
          <> "\n"
          <> blank_gutter
          <> string.repeat(" ", col)
          <> "^"
        }
        False -> do_source_context(rest, target, line_num + 1, line_end + 1)
      }
    }
  }
}
