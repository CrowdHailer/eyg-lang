import eyg/ir/tree as ir
import eyg/parser/debug
import eyg/parser/lexer
import eyg/parser/location
import eyg/parser/parser
import eyg/parser/token
import gleam/list
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
  let description = debug.describe(reason)
  let hint = debug.hint(reason)
  let span = case reason_position(reason) {
    Some(start) -> #(start, start)
    None -> #(0, 0)
  }
  render_error(description, hint, source, span)
}

pub fn render_error(description, hint, code, span) {
  let lines = ["error: " <> description, "hint: " <> hint]
  let context = case span {
    #(0, 0) -> []
    _ -> ["", ..location.source_context(code, span)]
  }
  string.join(list.append(lines, context), "\n")
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
    parser.InvalidReleaseVersion(pos) -> Some(pos)
    parser.InvalidImportPath(pos) -> Some(pos)
    parser.TrailingTokens(_, pos) -> Some(pos)
    parser.InvalidCharacter(_, pos) -> Some(pos)
    parser.UnterminatedStringLiteral(pos) -> Some(pos)
    parser.InvalidEscapeSequence(_, pos) -> Some(pos)
  }
}
