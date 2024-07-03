import eyg/parse/lexer
import eyg/parse/parser
import eyg/parse/token
import gleam/result

pub fn from_string(src) {
  src
  |> lexer.lex()
  |> token.drop_whitespace()
  |> parser.expression()
}

pub fn all_from_string(src) {
  use #(source, remaining) <- result.try(from_string(src))
  case remaining {
    [] -> Ok(source)
    [#(token, at), ..] -> Error(parser.UnexpectedToken(token, at))
  }
}
