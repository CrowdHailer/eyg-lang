import eyg/parse/lexer
import eyg/parse/parser

pub fn from_string(src) {
  src
  |> lexer.lex()
  |> parser.parse()
}
