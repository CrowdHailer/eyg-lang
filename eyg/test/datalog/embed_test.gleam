import gleam/io
import eyg/parse/lexer
import eyg/parse/parser
import gleeunit/should

pub fn next_test() {
  "solve T(query {
        T(x: 3, y: 2).
    })"
  |> lexer.lex()
  |> parser.parse()
  |> io.debug
  //   todo
}

// TODO CEK
// TODO infer