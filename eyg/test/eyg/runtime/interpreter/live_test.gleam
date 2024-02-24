import gleam/io
import gleam/dict
import eyg/parse/lexer
import eyg/parse/parser
import eyg/runtime/interpreter/live
import gleeunit/should

fn parse(src) {
  src
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
}

pub fn nuu_test() {
  "let f = ({x}) -> {
    x
    }
  let y = f({x:2})
  f({x:4})"
  |> parse
  |> live.execute()
  |> io.debug
  todo
}
