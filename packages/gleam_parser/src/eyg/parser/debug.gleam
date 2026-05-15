import eyg/parser/parser
import eyg/parser/token as t
import gleam/int
import gleam/string

pub fn describe(reason) {
  case reason {
    parser.UnexpectedToken(token:, position:) ->
      "unexpected `"
      <> t.to_string(token)
      <> "` at position "
      <> int.to_string(position)
    parser.UnexpectEnd -> "unexpected end of input"
    parser.InvalidCharacter(char:, position:) ->
      "invalid character '"
      <> char
      <> "' at position "
      <> int.to_string(position)
    parser.UnterminatedStringLiteral(position:) ->
      "unterminated string literal at position " <> int.to_string(position)
    parser.InvalidEscapeSequence(escape_char:, position:) ->
      "invalid escape sequence `\\"
      <> escape_char
      <> "` in string at position "
      <> int.to_string(position)
    parser.MissingEquals(position:) ->
      "expected `=` after let binding name at position "
      <> int.to_string(position)
    parser.MissingArrow(position:) ->
      "expected `->` followed by `{` in function definition at position "
      <> int.to_string(position)
    parser.UnclosedFunctionBody(open_at:) ->
      "unclosed function body — expected `}` to close the `{` opened at position "
      <> int.to_string(open_at)
    parser.ExpectedEffectName(keyword:, position:) ->
      "expected an uppercase effect name after `"
      <> keyword
      <> "` at position "
      <> int.to_string(position)
    parser.ExpectedBuiltinName(position:) ->
      "expected a builtin identifier after `!` at position "
      <> int.to_string(position)
    parser.InvalidCidReference(position:) ->
      "invalid content identifier (CID) at position " <> int.to_string(position)
    parser.InvalidReleaseVersion(position:) ->
      "expected an integer release version after `:` at position "
      <> int.to_string(position)
    parser.InvalidImportPath(position:) ->
      "expected a string path after `import` at position "
      <> int.to_string(position)
    parser.TrailingTokens(token:, position:) -> {
      let token_str = case token {
        t.UnexpectedGrapheme(raw) -> string.slice(raw, 0, 1)
        _ -> t.to_string(token)
      }
      "unexpected `"
      <> token_str
      <> "` at position "
      <> int.to_string(position)
      <> " — the expression is complete but there are leftover tokens"
    }
  }
}

pub fn hint(reason) {
  case reason {
    parser.UnexpectedToken(..) -> "view the syntax guide"
    parser.UnexpectEnd -> "program must end with valid expression"
    parser.InvalidCharacter(..) ->
      "remove or replace this character — EYG does not use it"
    parser.UnterminatedStringLiteral(..) ->
      "close the string with a double-quote `\"`"
    parser.InvalidEscapeSequence(..) ->
      "valid escapes are \\n (newline), \\t (tab), \\r (carriage return), \\\" (quote), \\\\ (backslash)"
    parser.MissingEquals(..) ->
      "let bindings use the form `let name = expression`"
    parser.MissingArrow(..) -> "functions are written as `(arg) -> { body }`"
    parser.UnclosedFunctionBody(..) ->
      "every `{` in a function body must be closed with `}`"
    parser.ExpectedEffectName(keyword:, ..) ->
      "effect names must start with an uppercase letter, e.g. `"
      <> keyword
      <> " Log`"
    parser.ExpectedBuiltinName(..) ->
      "builtins use lowercase names, e.g. `!int_add`"
    parser.InvalidCidReference(..) ->
      "CID references use a valid base32-encoded CID, e.g. `#bafyreig...`"
    parser.InvalidReleaseVersion(..) ->
      "pin a release with `@package:N` (e.g. `@tandard:3`) or omit `:` to track the latest"
    parser.InvalidImportPath(..) ->
      "import paths must be string literals, e.g. `import \"./module.eyg.json\"`"
    parser.TrailingTokens(token:, ..) -> {
      case token {
        t.Let ->
          "the previous expression already completed the block. If you meant the block to continue, bind that expression to `let _ = ...` first."
        _ -> "EYG uses function calls for operations, not infix operators"
      }
    }
  }
}
